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

/// Sends and receives messages for association.
///
/// These methods are all implemented in `AssociationManager` and the associator is just a proxy
/// which forwards these calls to the manager.
@MainActor protocol Associator {
  var connectionHandle: ConnectionHandle { get }

  var carId: String? { get nonmutating set }

  /// Request an out of band token.
  func requestOutOfBandToken(completion: @escaping (OutOfBandToken?) -> Void)

  /// Attempt to configure a secure channel using the specified message stream.
  func establishEncryption(using messageStream: MessageStream)

  /// Saves the secure session and establishes a secured car channel.
  func establishSecuredCarChannel(
    forCarId carId: String,
    messageStream: MessageStream
  ) -> SecuredConnectedDeviceChannel?

  /// Completes any remaining association work and notifies the delegate that
  /// association is complete.
  func completeAssociation(
    channel: SecuredConnectedDeviceChannel, messageStream: MessageStream)

  /// Display the specified pairing code for visual verification.
  func displayPairingCode(_ pairingCode: String)

  /// Notifies the delegate that an error has been encountered during the association process.
  func notifyDelegateOfError(_ error: AssociationError)

  /// Notifies the secure channel that the pairing code is complete.
  func notifyPairingCodeAccepted() throws
}

/// Delegate that will be notified of association statuses.
@MainActor protocol AssociationManagerDelegate: AnyObject {
  /// Invoked when the association manager has successfully completed associating the current
  /// device.
  ///
  /// - Parameters:
  ///   - associationManager: The association manager handling the association.
  ///   - car: The car that finished association.
  ///   - securedCarChannel: The channel the resulted from the association.
  func associationManager(
    _ associationManager: AssociationManager,
    didCompleteAssociationWithCar car: Car,
    securedCarChannel: SecuredConnectedDeviceChannel,
    peripheral: BLEPeripheral
  )

  /// Invoked during device id exchange when the car's device id is received.
  ///
  /// - Parameters:
  ///   - associationManager: The association manager handling the association.
  ///   - carId: The car's device id.
  func associationManager(
    _ associationManager: AssociationManager, didReceiveCarId carId: String)

  /// Invoked when the association manager requires the given pairing code to be displayed to the
  /// user so they can confirm that it matches the value on the car being associated.
  ///
  /// - Parameters:
  ///   - associationManager: The association manager handling association.
  ///   - pairingCode: The pairing code to display.
  func associationManager(
    _ associationManager: AssociationManager,
    requiresDisplayOf pairingCode: String
  )

  /// Invoked when the association manager has encountered an error during the association process.
  ///
  /// - Parameters:
  ///   - associationManager: The association manager handling the association.
  ///   - error: The error that occurred.
  func associationManager(_ associationManager: AssociationManager, didEncounterError error: Error)
}

/// Handles the process of pairing the current device with a specified car. The car should
/// be advertising that it supports the association of a companion phone.
@MainActor class AssociationManager: NSObject {
  private static let log = Logger(for: AssociationManager.self)

  private static let streamParams = MessageStreamParams(
    recipient: Config.defaultRecipientUUID, operationType: .clientMessage)

  /// The amount of time an association attempt has before it has been deemed to have timed out.
  static let defaultTimeoutDuration = DispatchTimeInterval.seconds(10)

  /// The value that should be sent by the head unit if the pairing code has been confirmed.
  ///
  /// Any other value than this should be treated as a rejection of the pairing code.
  static let pairingCodeConfirmationValue = "True"

  private static let isAssociatingKey = "isAssociatingKey"
  private static let associationCompletedKey = "associationCompletedKey"

  private let connectionHandle: ConnectionHandle
  private let uuidConfig: UUIDConfig
  private var associationUUID: CBUUID
  private let associatedCarsManager: AssociatedCarsManager
  private let secureSessionManager: SecureSessionManager
  private let messageHelperFactory: AssociationMessageHelperFactory
  private let outOfBandTokenProvider: OutOfBandTokenProvider

  /// The current car that is being associated.
  ///
  /// The peripheral needs to have strong reference to it; otherwise, it might be deallocated before
  /// association is complete. This ensures callbacks happen appropriately.
  private(set) var carToAssociate: BLEPeripheral?

  /// The characteristic on the car that can receive the token.
  ///
  /// Initialized when the peripheral's characteristics are discovered. If they are not discovered,
  /// then further action will not happen, so this force unwrap is safe.
  private var writeCharacteristic: BLECharacteristic!

  /// The characteristic on the car that can receive the handle.
  ///
  /// This value is initialized when the peripheral's characteristics are discovered. If they are
  /// not discovered, then further action will not happen, so this force unwrap is safe.
  private var readCharacteristic: BLECharacteristic!

  /// A work item that should be executed an association attempt has timed out.
  private var associationTimeout: DispatchWorkItem?

  private var secureBLEChannel: SecureBLEChannel
  private let bleVersionResolver: BLEVersionResolver

  /// Whether compression is allowed.
  let isMessageCompressionAllowed: Bool

  /// The stream that will handle sending messages.
  ///
  /// This stream will be initialized after characteristics are discovered.
  var messageStream: BLEMessageStream?

  var timeoutDuration = AssociationManager.defaultTimeoutDuration

  /// Id of car which is being associated.
  var carId: String? {
    willSet {
      guard let newCarId = newValue else { return }
      delegate?.associationManager(self, didReceiveCarId: newCarId)
    }
  }

  /// Delegate to be notified of various actions within the ConnectionManager.
  weak var delegate: AssociationManagerDelegate?

  private var messageHelper: AssociationMessageHelper?

  /// Whether any devices been been previously associated.
  var isAssociated: Bool {
    return associatedCarsManager.count > 0
  }

  /// The cars that are currently associated with this device.
  var cars: Set<Car> {
    return associatedCarsManager.cars
  }

  /// Creates an `AssociationManager` with the given storage options.
  ///
  /// - Parameters:
  ///   - overlay: Overlay of key/value pairs.
  ///   - connectionHandle: A handle for managing connections to remote cars.
  ///   - uuidConfig: The configuration for common UUIDs.
  ///   - associatedCarsManager: Manager for retrieving information about the car that is currently
  ///       associated with this device.
  ///   - secureSessionManager: Manager for retrieving and storing secure sessions.
  ///   - secureBLEChannel: The channel to handle the establishment of a secure connection.
  ///   - bleVersionResolver: The message stream version resolver.
  ///   - outOfBandTokenProvider: Provider tokens for out of band association verification.
  ///   - messageHelperFactory: The factory for making the message exchange helper.
  init(
    overlay: Overlay,
    connectionHandle: ConnectionHandle,
    uuidConfig: UUIDConfig,
    associatedCarsManager: AssociatedCarsManager,
    secureSessionManager: SecureSessionManager,
    secureBLEChannel: SecureBLEChannel,
    bleVersionResolver: BLEVersionResolver,
    outOfBandTokenProvider: OutOfBandTokenProvider,
    messageHelperFactory: AssociationMessageHelperFactory =
      AssociationMessageHelperFactoryImpl()
  ) {
    self.connectionHandle = connectionHandle
    self.uuidConfig = uuidConfig
    associationUUID = uuidConfig.associationUUID
    self.associatedCarsManager = associatedCarsManager
    self.secureSessionManager = secureSessionManager
    self.secureBLEChannel = secureBLEChannel
    self.bleVersionResolver = bleVersionResolver
    self.outOfBandTokenProvider = outOfBandTokenProvider
    self.messageHelperFactory = messageHelperFactory

    isMessageCompressionAllowed = overlay.isMessageCompressionAllowed

    super.init()
    self.secureBLEChannel.delegate = self
  }

  /// Associates this current device with the given peripheral.
  ///
  /// The given peripheral should be connected to the current device. When association is complete,
  /// delegates will be notified via their `didCompleteAssociationWithCar` method.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to associate with.
  ///   - config: A configuration object for modifying the current scan.
  func associate(_ peripheral: BLEPeripheral, config: AssociationConfig) {
    resetInternalState()
    outOfBandTokenProvider.prepareForRequests()

    associationUUID = config.associationUUID

    carToAssociate = peripheral

    peripheral.delegate = self

    scheduleAssociationTimeout(for: peripheral)
    peripheral.discoverServices([associationUUID])
  }

  private func scheduleAssociationTimeout(for peripheral: BLEPeripheral) {
    let notifyAssociationError = DispatchWorkItem { [weak self] in
      Self.log.error(
        "Association attempt timed out for car \(peripheral.logName). Notifying delegate.")

      self?.notifyDelegateOfError(.timedOut)
    }
    associationTimeout = notifyAssociationError

    DispatchQueue.main.asyncAfter(
      deadline: .now() + timeoutDuration,
      execute: notifyAssociationError
    )
  }

  /// Unregisters all devices that were previously associated and clears any current association
  /// attempts.
  func clearAllAssociations() {
    resetInternalState()
    outOfBandTokenProvider.reset()
    associatedCarsManager.identifiers.forEach {
      secureSessionManager.clearSecureSession(for: $0)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: $0)
    }
    associatedCarsManager.clearIdentifiers()
  }

  /// Clears the association for the specified car.
  ///
  /// - Parameter car: The car to be removed.
  func clearAssociation(for car: Car) {
    outOfBandTokenProvider.reset()
    secureSessionManager.clearSecureSession(for: car.id)
    associatedCarsManager.clearIdentifier(car.id)
    try? CarAuthenticatorImpl.removeKey(forIdentifier: car.id)
  }

  /// Renames an associated car.
  ///
  /// - Parameters:
  ///   - carId: The ID of the car to rename.
  ///   - name: The new name for the car.
  /// - Returns: `true` if the name was changed successfully.
  func renameCar(withId carId: String, to name: String) -> Bool {
    return associatedCarsManager.renameCar(identifier: carId, to: name)
  }

  /// Clear internal state for current association.
  func clearCurrentAssociation() {
    resetInternalState()
    outOfBandTokenProvider.reset()
  }

  /// Reset to the default state before a device is to be associated.
  private func resetInternalState() {
    associationTimeout?.cancel()

    associationUUID = uuidConfig.associationUUID

    messageStream = nil
    writeCharacteristic = nil
    readCharacteristic = nil
    carToAssociate = nil
    carId = nil
    messageHelper = nil
  }

  /// Checks if the given peripheral has an association characteristic for registering an escrow
  /// token with.
  ///
  /// - Parameters:
  ///   - characteristics: The array of characteristics to process.
  ///   - peripheral: The peripheral that hosts the given characteristics
  private func process(_ characteristics: [BLECharacteristic], for peripheral: BLEPeripheral) {
    for characteristic in characteristics {
      Self.log.debug("Processing association characteristic: \(characteristic.uuid.uuidString)")

      switch characteristic.uuid {
      case UUIDConfig.writeCharacteristicUUID:
        writeCharacteristic = characteristic
      case UUIDConfig.readCharacteristicUUID:
        readCharacteristic = characteristic
      default:
        Self.log.debug(
          "Encountered unknown associate characteristic uuid: \(characteristic.uuid.uuidString)"
        )
      }
    }
  }

  private func establishEncryption(using messageStream: BLEMessageStream) {
    Self.log("Attempting to establish encryption with \(messageStream.peripheral.logName)")

    do {
      try secureBLEChannel.establish(using: messageStream)
    } catch {
      delegate?.associationManager(self, didEncounterError: error)
    }
  }

  /// Attempts to save the session for the specified carId.
  ///
  /// - Parameter carId: The carId for which to save the session
  /// - Returns: `true` if the session was successfully saved
  private func saveSecureSession(for carId: String) -> Bool {
    guard let savedSession = try? secureBLEChannel.saveSession(),
      secureSessionManager.storeSecureSession(savedSession, for: carId)
    else {
      Self.log.error("Cannot save the secure session. Cannot complete association.")
      notifyDelegateOfError(.cannotStoreAssociation)
      return false
    }

    return true
  }

  private func establishSecuredCarChannel(
    forCarId carId: String,
    messageStream: BLEMessageStream
  ) -> SecuredConnectedDeviceChannel? {
    let name = messageStream.peripheral.name
    let car = Car(id: carId, name: name)

    guard saveSecureSession(for: carId) else { return nil }

    associatedCarsManager.addAssociatedCar(identifier: carId, name: name)

    return EstablishedCarChannel(
      car: car,
      connectionHandle: connectionHandle,
      messageStream: messageStream
    )
  }

  private func completeAssociation(
    channel: SecuredConnectedDeviceChannel,
    messageStream: BLEMessageStream
  ) {
    resetInternalState()
    outOfBandTokenProvider.closeForRequests()
    delegate?.associationManager(
      self,
      didCompleteAssociationWithCar: channel.car,
      securedCarChannel: channel,
      peripheral: messageStream.peripheral
    )
  }

  /// Request an out of band token.
  private func requestOutOfBandToken(completion: @escaping (OutOfBandToken?) -> Void) {
    outOfBandTokenProvider.requestToken(completion: completion)
  }

  private func notifyPairingCodeAccepted() throws {
    try secureBLEChannel.notifyPairingCodeAccepted()
  }

  private func displayPairingCode(_ pairingCode: String) {
    delegate?.associationManager(self, requiresDisplayOf: pairingCode)
    messageHelper?.onPairingCodeDisplayed()
  }

  /// Convenience method to notify an attached delegate of the given error.
  ///
  /// - Parameter error: The error to send to the delegate.
  private func notifyDelegateOfError(_ error: AssociationError) {
    associationTimeout?.cancel()
    outOfBandTokenProvider.closeForRequests()
    delegate?.associationManager(self, didEncounterError: error)
  }
}

// MARK: - CBPeripheralDelegate
extension AssociationManager: BLEPeripheralDelegate {
  func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?) {
    if let error = error {
      Self.log.error("Error discovering services: \(error.localizedDescription)")
      notifyDelegateOfError(.cannotDiscoverServices)
      return
    }

    guard let services = peripheral.services, services.count > 0 else {
      Self.log.error("No services in the given peripheral")
      notifyDelegateOfError(.cannotDiscoverServices)
      return
    }

    Self.log.info("Discovered \(services.count) services.")

    for service in services {
      Self.log.debug("Service UUID: \(service.uuid.uuidString)")

      if service.uuid == associationUUID {
        Self.log.debug("Discovering characteristics for association service.")

        peripheral.discoverCharacteristics(
          [
            UUIDConfig.readCharacteristicUUID,
            UUIDConfig.writeCharacteristicUUID,
          ],
          for: service
        )
      }
    }
  }

  func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  ) {
    if let error = error {
      Self.log.error("Error discovering characteristics: \(error.localizedDescription)")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    guard service.uuid == associationUUID else {
      Self.log.error("Encountered unknown UUID: \(service.uuid.uuidString)")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    guard let characteristics = service.characteristics, characteristics.count > 0 else {
      Self.log.error("No characteristics discovered for the peripheral.")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    Self.log.debug(
      "Discovered \(characteristics.count) characteristics for service \(service.uuid.uuidString)"
    )

    process(characteristics, for: peripheral)

    guard writeCharacteristic != nil else {
      Self.log.error("Could not find associate characteristic for client write.")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    guard readCharacteristic != nil else {
      Self.log.error("Could not find associate characteristic for server write.")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    bleVersionResolver.delegate = self
    bleVersionResolver.resolveVersion(
      with: peripheral,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: true
    )
  }

  func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    // No-op
  }

  func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral) {
    // No-op.
  }
}

// MARK: - SecureBLEChannelDelegate

extension AssociationManager: SecureBLEChannelDelegate {
  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    requiresVerificationOf verificationToken: SecurityVerificationToken,
    messageStream: MessageStream
  ) {
    // User input is required at this step, so the timeout is no longer needed.
    associationTimeout?.cancel()

    messageStream.delegate = self
    messageHelper?.onRequiresPairingVerification(verificationToken)
  }

  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    establishedUsing messageStream: MessageStream
  ) {
    messageHelper?.onEncryptionEstablished()
  }

  func secureBLEChannel(_ secureBLEChannel: SecureBLEChannel, encounteredError error: Error) {
    delegate?.associationManager(self, didEncounterError: error)
  }
}

// MARK: - MessageStreamDelegate

extension AssociationManager: MessageStreamDelegate {
  func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {
    Self.log.debug("Received message from characteristic \(messageStream.readingDebugDescription).")

    messageHelper?.handleMessage(message, params: params)
  }

  func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {
    Self.log.error(
      """
      Error writing escrow token for characteristic \
      (\(messageStream.writingDebugDescription)): \(error.localizedDescription)
      """
    )

    notifyDelegateOfError(.cannotSendMessages)
  }

  func messageStreamDidWriteMessage(
    _ messageStream: MessageStream,
    to recipient: UUID
  ) {
    messageHelper?.messageDidSendSuccessfully()
  }
}

// MARK: - BLEVersionResolverDelegate

extension AssociationManager: BLEVersionResolverDelegate {
  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didResolveStreamVersionTo streamVersion: MessageStreamVersion,
    securityVersionTo securityVersion: MessageSecurityVersion,
    for peripheral: BLEPeripheral
  ) {
    // This shouldn't happen because the version exchange happens after characteristics are
    // discovered.
    guard let readCharacteristic = readCharacteristic,
      let writeCharacteristic = writeCharacteristic
    else {
      Self.log.error("Could not find read and write characteristics after BLE version resolution.")
      notifyDelegateOfError(.cannotDiscoverCharacteristics)
      return
    }

    let messageStream = BLEMessageStreamFactory.makeStream(
      version: streamVersion,
      peripheral: peripheral,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCompression: isMessageCompressionAllowed
    )
    self.messageStream = messageStream
    messageStream.delegate = self

    let associator = AssociatorProxy(self)
    messageHelper = messageHelperFactory.makeHelper(
      associator: associator, securityVersion: securityVersion, messageStream: messageStream)
    messageHelper?.start()
  }

  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didEncounterError error: BLEVersionResolverError,
    for peripheral: BLEPeripheral
  ) {
    notifyDelegateOfError(.cannotSendMessages)
  }

  func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {
    Self.log.error(
      "Underlying BLEMessageStream encountered unrecoverable error. Notifying delegate."
    )
    notifyDelegateOfError(.unknown)
  }

  /// Proxy for `AssociationManager` conforming to `Associator` so we can keep those
  /// members private as needed and only expose them to the helper.
  private struct AssociatorProxy: Associator {
    private unowned let manager: AssociationManager

    init(_ manager: AssociationManager) {
      self.manager = manager
    }

    var connectionHandle: ConnectionHandle { manager.connectionHandle }

    var carId: String? {
      get { manager.carId }
      nonmutating set { manager.carId = newValue }
    }

    func requestOutOfBandToken(completion: @escaping (OutOfBandToken?) -> Void) {
      manager.requestOutOfBandToken(completion: completion)
    }

    func establishEncryption(using messageStream: MessageStream) {
      guard let bleMessageStream = messageStream as? BLEMessageStream else {
        fatalError("MessageStream: \(messageStream) is expected to be a BLEMessageStream.")
      }
      manager.establishEncryption(using: bleMessageStream)
    }

    func establishSecuredCarChannel(
      forCarId carId: String,
      messageStream: MessageStream
    ) -> SecuredConnectedDeviceChannel? {
      guard let bleMessageStream = messageStream as? BLEMessageStream else {
        fatalError("MessageStream: \(messageStream) is expected to be a BLEMessageStream.")
      }
      return manager.establishSecuredCarChannel(forCarId: carId, messageStream: bleMessageStream)
    }

    func completeAssociation(
      channel: SecuredConnectedDeviceChannel, messageStream: MessageStream
    ) {
      guard let bleMessageStream = messageStream as? BLEMessageStream else {
        fatalError("MessageStream: \(messageStream) is expected to be a BLEMessageStream.")
      }
      manager.completeAssociation(channel: channel, messageStream: bleMessageStream)
    }

    func displayPairingCode(_ pairingCode: String) {
      manager.displayPairingCode(pairingCode)
    }

    func notifyDelegateOfError(_ error: AssociationError) {
      manager.notifyDelegateOfError(error)
    }

    func notifyPairingCodeAccepted() throws {
      try manager.notifyPairingCodeAccepted()
    }
  }
}
