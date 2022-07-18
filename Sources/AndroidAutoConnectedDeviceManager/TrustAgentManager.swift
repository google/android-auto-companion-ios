// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import AndroidAutoLogger
@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation
@_implementationOnly import AndroidAutoTrustAgentProtos

#if canImport(UIKit)
  import UIKit
#endif

typealias TrustedDeviceMessage = Aae_Trustagent_TrustedDeviceMessage
typealias PhoneCredentials = Aae_Trustagent_PhoneCredentials
typealias TrustedDeviceState = Aae_Trustagent_TrustedDeviceState

/// Manages all functionality related to unlocking a previously associated car.
///
/// The trusted device feature allows a phone to dismiss the lock screen on an Android-powered
/// head unit if that car is in range. In order for this feature to work, the phone must first
/// be "enrolled" with the car. After enrollment, this feature will automatically handle the
/// unlock without user interaction.
///
/// Utilize the `enroll(_:)` method to handle enrollment, and `stopEnrollment(_:)` to remove any
/// previous enrollments. If a car is disassociated, then that car's enrollment status is
/// cleared.
///
/// By default, this manager keeps track of the dates in which a successful unlock has occurred up
/// to a maximum of 14 days. Use the method `clearUnlockHistory(for:)` to clear all dates. To
/// disable this storage entirely, create a `trust_agent_manager.plist` file and add the following
/// entry:
///
/// ```
/// <key>UnlockHistoryEnabled</key>
/// <false/>
/// ```
public class TrustAgentManager: FeatureManager {
  private static let log = Logger(for: TrustAgentManager.self)

  private static let signpostMetrics = SignpostMetrics(category: "TrustAgentManager")

  private enum Signposts {
    static let enrollmentDuration = SignpostDuration("Enrollment Duration")
    static let enrollmentCompletion = SignpostMarker("Enrollment Completion")
    static let enrollmentFailure = SignpostMarker("Enrollment Failure")
    static let unenrollment = SignpostMarker("Unenrollment")
    static let unlockedCar = SignpostMarker("Unlocked Car")
    static let unlockedCarFailure = SignpostMarker("Unlock Car Failure")
    static let unlockingCarDuration = SignpostDuration("Unlocking Car Duration")
  }

  /// The name of a `.plist` file that should contain configuration files.
  private static let plistFileName = "trust_agent_manager"

  static let version: Int32 = 2
  static let recipientUUID = UUID(uuidString: "85dff28b-3036-4662-bb22-baa7f898dc47")!

  fileprivate let escrowTokenManager: EscrowTokenManager

  private let config: TrustAgentConfig
  private let trustAgentStorage: TrustAgentManagerStorage

  private var deviceUnlockObserver: NSObjectProtocol?

  /// Dictionary of car ids for cars currently enrolling to a boolean indicating if the enrollment
  /// was initiated by that car.
  private var enrollingCars: [String: Bool] = [:]

  public override var featureID: UUID {
    return Self.recipientUUID
  }

  /// Delegate to be notified of status updates within the TrustAgentManager.
  public weak var delegate: TrustAgentManagerDelegate?

  /// Whether a passcode is required for enrolling and unlocking.
  ///
  /// By default, this value is `true`.
  public var isPasscodeRequired: Bool {
    get {
      return config.isPasscodeRequired
    }
    set {
      config.isPasscodeRequired = newValue
    }
  }

  /// Creates an `TrustAgentManager`.
  ///
  /// Upon creation, the manager will start listening for connections of cars that have been
  /// enrolled in the trust agent feature and unlock them if appropriate.
  ///
  /// To enroll a car with the feature, call `enroll(_:)`.
  ///
  /// - Parameter connectedCarManager: The manager of cars connecting to the current device.
  override public convenience init(connectedCarManager: ConnectedCarManager) {
    self.init(
      connectedCarManager: connectedCarManager,
      escrowTokenManager: KeychainEscrowTokenManager(),
      trustAgentStorage: UserDefaultsTrustAgentManagerStorage(),
      config: TrustAgentConfigUserDefaults(
        plistLoader: PListLoaderImpl(plistFileName: Self.plistFileName)
      )
    )
  }

  init(
    connectedCarManager: ConnectedCarManager,
    escrowTokenManager: EscrowTokenManager,
    trustAgentStorage: TrustAgentManagerStorage,
    config: TrustAgentConfig
  ) {
    self.escrowTokenManager = escrowTokenManager
    self.trustAgentStorage = trustAgentStorage
    self.config = config

    super.init(connectedCarManager: connectedCarManager)

    Self.log(
      "Initializing TrustAgentManager. Unlock history enabled: \(config.isUnlockHistoryEnabled)")

    // Clear any stored unlock history to catch cases where the config has been changed from `true`
    // to `false`.
    if !config.isUnlockHistoryEnabled {
      trustAgentStorage.clearAllUnlockHistory()
    }

    // Whenever the device is unlocked, resend the credentials for the connected cars.
    #if os(iOS)
      deviceUnlockObserver = NotificationCenter.default.addObserver(
        forName: UIApplication.protectedDataDidBecomeAvailableNotification,
        object: nil,
        queue: OperationQueue.main
      ) { [unowned self] notification in
        Self.log("Device Unlocked - sending credentials for connected cars.")
        self.sendCredentialsForDeviceUnlockRequiredCars()
      }
    #else
      // TODO(b/152639737): provide alternative for watchOS
    #endif
  }

  deinit {
    if let unlockObserver = deviceUnlockObserver {
      NotificationCenter.default.removeObserver(unlockObserver)
    }
  }

  /// Enrolls the given car with the trust agent feature.
  ///
  /// If enrollment was successful, the delegate will be notified via a call to
  /// `trustAgentManager(_:didCompleteEnrolling)`.
  ///
  /// After enrollment is successful, the given car will be automatically unlocked if this
  /// phone is detected nearby.
  ///
  /// - Parameter car: The car to enroll.
  public func enroll(_ car: Car) throws {
    try enroll(car, isInitiatedFromCar: false)
  }

  private func enroll(_ car: Car, isInitiatedFromCar: Bool) throws {
    guard config.arePasscodeRequirementsMet() else {
      Self.log.error("Cannot enroll since passcode has not been set on this device.")
      throw TrustAgentManagerError.passcodeNotSet
    }

    guard isCarSecurelyConnected(car) else {
      Self.log.error(
        """
        Request to enroll car (\(car.logName) but that specified car is not connected. \
        Ignoring request.
        """
      )
      notifyDelegateOfEnrollingError(.carNotConnected, car: car)
      return
    }

    guard let escrowToken = escrowTokenManager.generateAndStoreToken(for: car.id) else {
      Self.log.error("Error generating and storing escrow token.")
      notifyDelegateOfEnrollingError(.cannotGenerateToken, car: car)
      return
    }

    Self.log(
      """
      Sending escrow token to associated car: \(car.logName). \
      Initiated from car: \(isInitiatedFromCar)
      """
    )

    enrollingCars[car.id] = isInitiatedFromCar
    sendEscrowToken(escrowToken, to: car)
  }

  /// Stops an enrollment attempt with the given car.
  ///
  /// - Parameter car: The car to stop enrollment for.
  public func stopEnrollment(for car: Car) {
    Self.signpostMetrics.postIfAvailable(Signposts.unenrollment)
    clearEnrollment(for: car, syncToCar: true, initiatedFromCar: false)
    enrollingCars.removeValue(forKey: car.id)
  }

  /// Whether this device is required to be unlocked for unlocking the head unit. By default, this
  /// value is `false`.
  ///
  /// - Returns: `true` if this device needs to be unlocked to unlock the given car.
  public func isDeviceUnlockRequired(for car: Car) -> Bool {
    return config.isDeviceUnlockRequired(for: car)
  }

  /// Sets whether user needs to unlock their phone to unlock the given car.
  ///
  /// - Parameters:
  ///   - isRequired: `true` if unlocking of the phone is required.
  ///   - car: The car to set the value for.
  public func setDeviceUnlockRequired(_ isRequired: Bool, for car: Car) {
    config.setDeviceUnlockRequired(isRequired, for: car)
  }

  /// Check the enrollment status of the feature regarding the car with id `carId`.
  ///
  /// - Parameter car: The car that we want to check the enrollment status for.
  /// - Returns: `true` if the trusted device feature is enrolled for the car with id `carId`.
  public func isEnrolled(with car: Car) -> Bool {
    return escrowTokenManager.token(for: car.id) != nil
      && escrowTokenManager.handle(for: car.id) != nil
  }

  /// Returns the unlock history for a car, sorted from oldest to newest.
  ///
  /// - Parameter car: The car that we should get the unlock history for.
  /// - Returns: The array of dates for previous unlock events, or an empty array if no history
  public func unlockHistory(for car: Car) -> [Date] {
    return trustAgentStorage.unlockHistory(for: car)
  }

  /// Clears all stored unlock history for the given car.
  ///
  /// If the given car does not have any stored unlock history, or is not enrolled with this
  /// feature, then this method call will do nothing.
  ///
  /// - Parameter car: The car whose unlock history should be cleared.
  public func clearUnlockHistory(for car: Car) {
    trustAgentStorage.clearUnlockHistory(for: car)
  }

  // MARK: - Event methods.

  public override func onCarDisconnected(_ car: Car) {
    // If the car was currently enrolling, that process can't continue anymore.
    if enrollingCars[car.id] != nil {
      notifyDelegateOfEnrollingError(.carNotConnected, car: car)
      enrollingCars.removeValue(forKey: car.id)
    }
  }

  public override func onSecureChannelEstablished(for car: Car) {
    let enrolled = isEnrolled(with: car)

    Self.log("Car \(car.logName) connected securely. Currently enrolled: \(enrolled)")

    if enrolled {
      sendPhoneCredentials(to: car)
    } else {
      maybeSyncFeatureStatus(with: car)
    }
  }

  public override func onCarDisassociated(_ car: Car) {
    Self.log("Car \(car.logName) disassociated.")
    clearEnrollment(for: car, syncToCar: false, initiatedFromCar: false)
    trustAgentStorage.clearFeatureStatus(for: car)
  }

  public override func onMessageReceived(_ message: Data, from car: Car) {
    guard let trustedDeviceMessage = try? TrustedDeviceMessage(serializedData: message) else {
      Self.log.error("Failed to decode message from serialized data.")
      // Simply ignore invalid messages.
      return
    }

    handleTrustedDeviceMessage(trustedDeviceMessage, from: car)
  }

  // MARK: - Private methods.

  /// Clears the enrollment status for the given `car`.
  ///
  /// If `syncToCar` is `true`, then this phone will also notify the given car (if connected) to
  /// inform it that the enrollment has been disabled.
  ///
  /// - Parameters:
  ///   - car: The car to clear the enrollment status of.
  ///   - syncToCar: `true` if the given car should also be notified of the enrollment change.
  ///   - initiatedFromCar: `true` if the feature was turned off by the car.
  private func clearEnrollment(for car: Car, syncToCar: Bool, initiatedFromCar: Bool) {
    Self.log("Clearing enrollment status for (\(car.logName)). Removing any tokens and handles.")

    let enrolled = isEnrolled(with: car)

    escrowTokenManager.clearToken(for: car.id)
    escrowTokenManager.clearHandle(for: car.id)

    config.clearConfig(for: car)
    trustAgentStorage.clearUnlockHistory(for: car)

    guard enrolled else { return }

    // Only need to sync the status to the car if previously enrolled.
    if syncToCar {
      syncDisabledFeatureStatus(with: car)
    }

    delegate?.trustAgentManager(self, didUnenroll: car, initiatedFromCar: initiatedFromCar)
  }

  /// Attempts to sync whether the trusted device feature is currently enabled with the given car.
  ///
  /// If the car is currently connected, immediately send the status. Otherwise, store it until the
  /// next time the car connects.
  private func syncDisabledFeatureStatus(with car: Car) {
    guard let featureStatus = try? makeDisabledFeatureStatus() else {
      Self.log.error("Unable to create disabled feature status to send to car \(car.logName).")
      return
    }

    if securedCars.contains(car) {
      Self.log("Car \(car.logName) currently connected. Syncing feature status with it.")

      // If the send fails, save it to send next time the car connects. This will be cleared on
      // successful enrollment.
      if !sendFeatureStatus(featureStatus, to: car) {
        trustAgentStorage.storeFeatureStatus(featureStatus, for: car)
      }
      return
    }

    Self.log(
      """
      Car \(car.logName)'s enrollment status cleared, but not currently connected.
      Saving status to send on next connection.
      """
    )

    trustAgentStorage.storeFeatureStatus(featureStatus, for: car)
  }

  private func sendFeatureStatus(_ featureStatus: Data, to car: Car) -> Bool {
    do {
      try sendMessage(featureStatus, to: car)
      return true
    } catch {
      Self.log.error("Unable to send feature status to car: \(error.localizedDescription)")
      return false
    }
  }

  /// Sends a generated `escrowToken` to the given car.
  private func sendEscrowToken(_ escrowToken: Data, to car: Car) {
    do {
      let messageData = try makeMessageData(type: .escrowToken, payload: escrowToken)
      try sendMessage(messageData, to: car) { [weak self] success in
        if !success {
          self?.notifyDelegateOfEnrollingError(.cannotSendToken, car: car)
        }
      }
    } catch {
      Self.log.error("Error when sending escrow token to car: \(car.logName)")

      notifyDelegateOfEnrollingError(.cannotSendToken, car: car)
      return
    }
  }

  /// Checks if the given `car` has a pending enrollment status to be synced and syncs it if such a
  /// message exists.
  private func maybeSyncFeatureStatus(with car: Car) {
    guard let featureStatus = trustAgentStorage.featureStatus(for: car) else {
      Self.log.debug("Car \(car.logName) does not have any stored feature status messages to send.")
      return
    }

    Self.log("Car \(car.logName) has stored feature status messages to sync. Sending to car.")

    if sendFeatureStatus(featureStatus, to: car) {
      trustAgentStorage.clearFeatureStatus(for: car)
    }
  }

  private func sendPhoneCredentials(to car: Car) {
    guard let token = escrowTokenManager.token(for: car.id) else {
      Self.log("No token found for car \(car.logName). Meaning it is not enrolled")
      return
    }

    guard let handle = escrowTokenManager.handle(for: car.id) else {
      Self.log("No handle found for car \(car.logName). Meaning it is not enrolled")
      return
    }

    guard config.arePasscodeRequirementsMet() else {
      Self.log.error(
        "Cannot send unlock credentials since passcode has not been set on this device.")
      delegate?.trustAgentManager(self, didEncounterUnlockErrorFor: car, error: .passcodeNotSet)
      return
    }

    guard config.areLockStateRequirementsMet(for: car) else {
      Self.log.error("Cannot send unlock credentials since this device is locked.")
      delegate?.trustAgentManager(self, didEncounterUnlockErrorFor: car, error: .deviceLocked)
      return
    }

    guard let phoneCredentials = try? makePhoneCredentials(token: token, handle: handle) else {
      Self.log.error("Unable to combine token and handle to be sent to car \(car.logName).")
      delegate?.trustAgentManager(
        self, didEncounterUnlockErrorFor: car, error: .cannotSendCredentials)
      return
    }

    guard isCarSecurelyConnected(car) else {
      Self.log("Car (\(car.logName)) to use for sending unlock credentials is invalid. Ignoring.")
      return
    }

    Self.log(
      "Sending unlock credentials to car (\(car.logName))",
      metadata: ["action": "unlock", "car": car.logName]
    )

    Self.signpostMetrics.postIfAvailable(Signposts.unlockingCarDuration.begin)
    delegate?.trustAgentManager(self, didStartUnlocking: car)

    do {
      let messageData = try makeMessageData(type: .unlockCredentials, payload: phoneCredentials)
      try sendMessage(messageData, to: car)
    } catch {
      Self.log.error("Error sending unlock credentials to car (\(car.logName))")

      Self.signpostMetrics.postIfAvailable(Signposts.unlockingCarDuration.end)
      Self.signpostMetrics.postIfAvailable(Signposts.unlockedCarFailure)

      delegate?.trustAgentManager(
        self, didEncounterUnlockErrorFor: car, error: .cannotSendCredentials)
    }
  }

  private func handleTrustedDeviceMessage(_ message: TrustedDeviceMessage, from car: Car) {
    Self.log.debug("Received message of type \(message.type.rawValue).")

    switch message.type {
    case .ack:
      handleAcknowledgmentMessage(from: car)
    case .handle:
      processHandle(message.payload, from: car)
    case .startEnrollment:
      attemptEnrollment(with: car)
    case .stateSync:
      syncFeatureStatus(message.payload, from: car)
    default:
      Self.log.error("Unhandled message type \(message.type.rawValue)")
    }
  }

  private func attemptEnrollment(with car: Car) {
    Self.signpostMetrics.postIfAvailable(Signposts.enrollmentDuration.begin)

    do {
      Self.log(
        "Received enrollment request from car (\(car.logName)). Attempting to send escrow token.")

      try enroll(car, isInitiatedFromCar: true)
    } catch {
      guard let trustError = error as? TrustAgentManagerError else {
        Self.log.error(
          """
          Encountered unknown error when car has requested to enroll:
          \(error.localizedDescription)
          """
        )
        return
      }

      sendEnrollmentFailureMessage(to: car, error: trustError)
      delegate?.trustAgentManager(self, didEncounterEnrollingErrorFor: car, error: trustError)
    }
  }

  private func sendEnrollmentFailureMessage(to car: Car, error trustError: TrustAgentManagerError) {
    Self.signpostMetrics.postIfAvailable(Signposts.enrollmentFailure)

    do {
      var responseError = Aae_Trustagent_TrustedDeviceError()
      if case .passcodeNotSet = trustError {
        responseError.type = .deviceNotSecured
      } else {
        responseError.type = .messageTypeUnknown
      }
      let payload = try responseError.serializedData()
      let messageData = try makeMessageData(type: .error, payload: payload)
      try sendMessage(messageData, to: car)
    } catch {
      Self.log.error(
        "Error sending enrollment error response back to car: \(error.localizedDescription)")
    }
  }

  private func handleAcknowledgmentMessage(from car: Car) {
    Self.log(
      "Successfully unlocked car (\(car.logName))",
      metadata: ["car": car.logName, "unlocked": true]
    )

    if config.isUnlockHistoryEnabled {
      let unlockDate = Date()
      trustAgentStorage.addUnlockDate(unlockDate, for: car)

      Self.log.debug("Unlock history enabled. Storing unlock date: \(unlockDate)")
    }

    Self.signpostMetrics.postIfAvailable(Signposts.unlockingCarDuration.end)
    Self.signpostMetrics.postIfAvailable(Signposts.unlockedCar)

    delegate?.trustAgentManager(self, didSuccessfullyUnlock: car)
  }

  private func processHandle(_ handle: Data, from car: Car) {
    Self.log.debug("Received handle from head unit.")

    guard escrowTokenManager.storeHandle(handle, for: car.id) else {
      Self.log.error("Error during storage of handle.")
      delegate?.trustAgentManager(
        self, didEncounterEnrollingErrorFor: car, error: .cannotStoreHandle)
      return
    }

    sendHandleReceivedConfirmation(to: car)
  }

  /// Sends confirmation that the handle has been received.
  private func sendHandleReceivedConfirmation(to car: Car) {
    Self.log("Writing confirmation that handle has been received.")

    // Confirm receipt of handle
    do {
      let messageData = try makeMessageData(type: .ack)
      try sendMessage(messageData, to: car)

      Self.signpostMetrics.postIfAvailable(Signposts.enrollmentDuration.end)
      Self.signpostMetrics.postIfAvailable(Signposts.enrollmentCompletion)

      delegate?.trustAgentManager(
        self, didCompleteEnrolling: car,
        initiatedFromCar: enrollingCars[car.id] ?? false)

      // Enrollment complete, so remove from list of cars enrolling.
      enrollingCars.removeValue(forKey: car.id)

      // As precaution, also clear any feature syncs since these are no longer needed after a
      // successful enrollment.
      trustAgentStorage.clearFeatureStatus(for: car)
    } catch {
      Self.log.error("Cannot send confirmation message for association completion for sending")
      notifyDelegateOfEnrollingError(.cannotSendMessages, car: car)
      stopEnrollment(for: car)
    }
  }

  private func syncFeatureStatus(_ featureStatus: Data, from car: Car) {
    guard let status = try? TrustedDeviceState(serializedData: featureStatus) else {
      Self.log.error("Unable to parse feature status from \(car.logName). Ignoring.")
      return
    }

    Self.log.debug("Received feature status from \(car.logName). Enabled: \(status.enabled)")

    // The user could only turn off trusted device from the head unit when the phone is not
    // connected. Thus, only need to sync state if the feature is disabled. Otherwise, if the two
    // devices are connected and the feature is enabled, then the normal enrollment flow will be
    // triggered.
    if status.enabled {
      return
    }

    Self.log(
      """
      Car \(car.logName) has indicated trusted device feature has been disabled. \
      Clearing local enrollment.
      """
    )

    clearEnrollment(for: car, syncToCar: false, initiatedFromCar: true)
  }

  /// Creates a trusted device message from the specified type and optional payload.
  ///
  /// - Parameters:
  ///   - type: The message type.
  ///   - payload: The optional message payload data.
  /// - Returns: The generated trusted device message.
  private func makeMessage(
    type: TrustedDeviceMessage.MessageType,
    payload: Data? = nil
  ) -> TrustedDeviceMessage {
    var message = TrustedDeviceMessage()
    message.version = Self.version
    message.type = type
    if let payload = payload {
      message.payload = payload
    }
    return message
  }

  /// Creates a trusted device message from the specified type and optional payload.
  ///
  /// - Parameters:
  ///   - type: The message type.
  ///   - payload: The optional message payload data.
  /// - Returns: The generated trusted device message data.
  /// - Throws: An error if the message fails to serialize to data
  private func makeMessageData(
    type: TrustedDeviceMessage.MessageType,
    payload: Data? = nil
  ) throws -> Data {
    let message = makeMessage(type: type, payload: payload)
    return try message.serializedData()
  }

  /// Creates the authentication package that will be sent to the car to unlock it.
  ///
  /// - Parameters:
  ///   - token: The escrow token that was used to associate with a car.
  ///   - handle: The corresponding handle that was set by the car during association.
  /// - Returns: A `Data` object that encapsulates the two authentication parameters.
  /// - Throws: An error if a payload is unable to be created from the token and handle.
  private func makePhoneCredentials(token: Data, handle: Data) throws -> Data {
    var phoneCredentials = PhoneCredentials()

    phoneCredentials.escrowToken = token
    phoneCredentials.handle = handle

    return try phoneCredentials.serializedData()
  }

  /// Creates a feature status message to the car that will sync a disabled enrollment state.
  ///
  /// The only time a feature status should be sent to the car is if the feature has been disabled,
  /// since enabling will notify both sides that it has been turned on. As as result, the
  /// created message will indicate that the enrollment has been cleared.
  ///
  /// - Returns: The serialized proto to send to the car.
  /// - Throws: If there was an error creating the proto.
  private func makeDisabledFeatureStatus() throws -> Data {
    var status = TrustedDeviceState()
    status.enabled = false
    return try makeMessageData(type: .stateSync, payload: try status.serializedData())
  }

  /// Send the phone credentials for connected cars
  private func sendCredentialsForConnectedCars() {
    securedCars.forEach { car in
      Self.log.debug(
        "Found secure channel for car (\(car.logName)). Preparing to send unlock credentials.")

      sendPhoneCredentials(to: car)
    }
  }

  /// Send the phone credentials for connected cars which require the phone unlock
  private func sendCredentialsForDeviceUnlockRequiredCars() {
    securedCars
      .filter { isDeviceUnlockRequired(for: $0) }
      .forEach { car in
        Self.log.debug(
          "Found secure channel for car (\(car.logName)). Preparing to send unlock credentials.")

        sendPhoneCredentials(to: car)
      }
  }

  private func notifyDelegateOfEnrollingError(_ error: TrustAgentManagerError, car: Car) {
    delegate?.trustAgentManager(self, didEncounterEnrollingErrorFor: car, error: error)
  }
}
