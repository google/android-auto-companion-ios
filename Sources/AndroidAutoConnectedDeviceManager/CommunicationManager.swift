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

/// A delegate to be notified of the current state of secure communication establishment.
@MainActor protocol CommunicationManagerDelegate: AnyObject {
  /// Invoked when the process of encryption setup has begun.
  ///
  /// - Parameters:
  ///   - communicationManager: The manager handling secure channel establishment.
  ///   - car: The car for which the encryption setup is in progress.
  ///   - peripheral: The backing peripheral for the car.
  func communicationManager(
    _ communicationManager: CommunicationManager,
    establishingEncryptionWith car: Car,
    peripheral: BLEPeripheral
  )

  /// Invoked a given car has been set up for secure communication.
  ///
  /// - Parameters:
  ///   - communicationManager: The manager handling secure channel establishment.
  ///   - securedCarChannel: The channel that has successfully been established for secure
  ///     communication.
  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  )

  /// Invoked when an error has been encountered during the reconnection.
  ///
  /// - Parameters:
  ///   - communicationManager: The manager handling secure channel establishment.
  ///   - error: The error that was encountered.
  ///   - peripheral: The car a reconnection was attempted with.
  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEncounterError error: CommunicationManagerError,
    whenReconnecting peripheral: BLEPeripheral
  )
}

/// Possible errors that can result during a secure channel setup.
enum CommunicationManagerError: Error, Equatable {
  /// An unknown error occurred and connection could not be established.
  case unknown

  /// A secure channel was requested to be set up with a car that has not been associated yet.
  case notAssociated

  /// A secure channel cannot be reestablished with a given car because there is no saved
  /// encryption credentials for it.
  case noSavedEncryption

  /// Saved encryption session is invalid.
  case invalidSavedEncryption

  /// Failed to establish encryption.
  case failedEncryptionEstablishment

  /// The remote car does not contains the service that holds the characteristics to read from and
  /// write to.
  case serviceNotFound

  /// The remote car does not contain the characteristics to read from and write to.
  case characteristicsNotFound

  /// Attempted to connect with an unassociated car.
  case unassociatedCar

  /// The remote car is not responding to the reconnection flow with the right messages, meaning
  /// reconnection cannot occur.
  case invalidMessage

  /// The required advertisement data is missing.
  case missingAdvertisementData

  /// The required reconnection helper is missing for the specified peripheral `id`.
  case missingReconnectionHelper(UUID)

  /// The peripheral's version is not supported.
  case versionNotSupported

  /// Failed to resolve the version.
  case versionResolutionFailed

  /// The security version is unresolved.
  case unresolvedSecurityVersion

  /// The resolved security version doesn't match the helper's security version.
  case mismatchedSecurityVersion

  /// Attempt to configure a secure channel failed.
  case configureSecureChannelFailed
}

/// A manager responsible for handling communication with associated devices.
@MainActor class CommunicationManager: NSObject {
  private static let log = Logger(for: CommunicationManager.self)

  /// The amount of time a reconnection attempt has before it has been deemed to have timed out.
  static let defaultReconnectionTimeoutDuration = DispatchTimeInterval.seconds(10)

  /// The UUIDs of the read and write characteristics that correspond to the different services
  /// that are supported.
  typealias IOCharacteristicsUUIDs = (
    readUUID: CBUUID,
    writeUUID: CBUUID
  )

  static let versionCharacteristics: IOCharacteristicsUUIDs =
    (
      readUUID: UUIDConfig.readCharacteristicUUID,
      writeUUID: UUIDConfig.writeCharacteristicUUID
    )

  static let advertisementCharacteristicUUID = UUIDConfig.advertisementCharacteristicUUID

  static let acknowledgmentMessage = Data("ACK".utf8)

  /// Overlay key for the message compression enablement pending support for it.
  static let messageCompressionAllowedKey = "MessageCompressionAllowed"

  private let connectionHandle: ConnectionHandle
  private let uuidConfig: UUIDConfig
  private let associatedCarsManager: AssociatedCarsManager
  private let secureSessionManager: SecureSessionManager
  private let secureBLEChannelFactory: SecureBLEChannelFactory
  private let bleVersionResolver: BLEVersionResolver
  private let reconnectionHandlerFactory: ReconnectionHandlerFactory

  /// Maps identifiers for peripherals to a `DispatchWorkItem` keeping track that should be called
  /// if a reconnection attempt has timed out.
  private var reconnectionTimeouts: [UUID: DispatchWorkItem] = [:]

  /// Whether compression is allowed.
  let isMessageCompressionAllowed: Bool

  /// The cars waiting for a secure channel to be set up.
  var pendingCars: [PendingCar] = []

  /// Handlers that are currently in the middle of encryption setup.
  var reconnectingHandlers: [ReconnectionHandler] = []

  /// `ReconnectionHelper` keyed by peripheral id.
  var reconnectionHelpers: [UUID: ReconnectionHelper] = [:]

  var timeoutDuration = CommunicationManager.defaultReconnectionTimeoutDuration

  weak var delegate: CommunicationManagerDelegate?

  /// Creates a `CommunicationManager` with the given storage options.
  ///
  /// - Parameters:
  ///   - overlay: Overlay of key/value pairs.
  ///   - connectionHandle: A handle for managing connections to remote cars.
  ///   - uuidConfig: A configuration for common UUIDs.
  ///   - associatedCarsManager: Manager for retrieving information about the car that is currently
  ///       associated with this device.
  ///   - secureSessionManager: Manager for retrieving and storing secure sessions.
  ///   - secureBLEChannelFactory: A factory that can create new secure BLE channels.
  ///   - bleVersionResolver: The version of the message stream to use.
  ///   - reconnectionHandlerFactory: A factory that can create new `SecuredCarChannelInternal`s.
  init(
    overlay: Overlay,
    connectionHandle: ConnectionHandle,
    uuidConfig: UUIDConfig,
    associatedCarsManager: AssociatedCarsManager,
    secureSessionManager: SecureSessionManager,
    secureBLEChannelFactory: SecureBLEChannelFactory,
    bleVersionResolver: BLEVersionResolver,
    reconnectionHandlerFactory: ReconnectionHandlerFactory
  ) {
    self.connectionHandle = connectionHandle
    self.uuidConfig = uuidConfig
    self.associatedCarsManager = associatedCarsManager
    self.secureSessionManager = secureSessionManager
    self.secureBLEChannelFactory = secureBLEChannelFactory
    self.bleVersionResolver = bleVersionResolver
    self.reconnectionHandlerFactory = reconnectionHandlerFactory

    isMessageCompressionAllowed = overlay.isMessageCompressionAllowed
  }

  /// Add a helper to handle the reconnection handshake details.
  ///
  /// When a peripheral has been discovered, an appropriate helper must be assigned to this manager
  /// prior to initiating connection.
  ///
  /// - Parameter helper: The helper to handle reconnection handshake.
  func addReconnectionHelper(_ helper: ReconnectionHelper) {
    reconnectionHelpers[helper.peripheral.identifier] = helper
  }

  private func reconnectionHelper(for peripheral: BLEPeripheral) throws -> ReconnectionHelper {
    guard let helper = reconnectionHelpers[peripheral.identifier] else {
      throw CommunicationManagerError.missingReconnectionHelper(peripheral.identifier)
    }

    return helper
  }

  /// Starts the process of setting up a channel for secure communication with the given peripheral.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to set up secure communication with.
  ///   - id: A unique id that identifies the peripheral. This value can be `nil` if the id is not
  ///     known at the time of secure channel setup.
  func setUpSecureChannel(with peripheral: BLEPeripheral, id: String?) throws {
    let pendingCar: PendingCar
    let serviceUUIDToDiscover: CBUUID

    let helper = try reconnectionHelper(for: peripheral)
    if id != nil {
      let secureSession = try fetchSecureSession(for: peripheral, id: id!)
      pendingCar = PendingCar(car: peripheral, id: id!, secureSession: secureSession)
    } else {
      pendingCar = PendingCar(car: peripheral)
    }
    serviceUUIDToDiscover = helper.discoveryUUID(from: uuidConfig)

    pendingCars.append(pendingCar)

    peripheral.delegate = self

    scheduleReconnectionTimeout(for: peripheral)
    peripheral.discoverServices([serviceUUIDToDiscover])
  }

  private func scheduleReconnectionTimeout(for peripheral: BLEPeripheral) {
    let notifyReconnectionError = DispatchWorkItem { [weak self] in
      Self.log.error(
        "Reconnection attempt timed out for car \(peripheral.logName). Notifying delegate.")

      self?.notifyDelegateOfError(.failedEncryptionEstablishment, connecting: peripheral)
    }
    reconnectionTimeouts[peripheral.identifier] = notifyReconnectionError

    DispatchQueue.main.asyncAfter(
      deadline: .now() + timeoutDuration,
      execute: notifyReconnectionError
    )
  }

  /// Returns a saved secure session for the given car or throws an error if the car is
  /// unassociated.
  private func fetchSecureSession(for car: BLEPeripheral, id: String) throws -> Data {
    // Check if the peripheral matches the identifier of a previous association.
    guard associatedCarsManager.identifiers.contains(id) else {
      Self.log(
        """
        Attempted to set up secure channel with unassociated device (\(id). Expected ids: \
        \(associatedCarsManager.identifiers)
        """
      )
      throw CommunicationManagerError.notAssociated
    }

    guard let secureSession = secureSessionManager.secureSession(for: id) else {
      Self.log("No secure session found for car (id: \(id), name: \(car.logName)")
      throw CommunicationManagerError.noSavedEncryption
    }

    return secureSession
  }

  /// Attempts to resolve the version of the BLE message stream to use.
  ///
  /// The given characteristics are vetted to ensure that they contain the right ones that can
  /// receive the unlock signals. If they do not, then this method will do nothing.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to communicate with.
  ///   - characteristics: The characteristics of the given peripheral.
  private func resolveBLEVersion(
    with peripheral: BLEPeripheral,
    characteristics: [BLECharacteristic]
  ) {
    let ioCharacteristicsUUIDs = CommunicationManager.versionCharacteristics

    guard
      let (readCharacteristic, writeCharacteristic) =
        filter(characteristics, for: ioCharacteristicsUUIDs)
    else {
      Self.log.error("Missing characteristics for car \(peripheral.logName)")
      notifyDelegateOfError(.characteristicsNotFound, connecting: peripheral)
      return
    }

    guard let pendingCar = firstPendingCar(with: peripheral) else {
      Self.log.error("No pending car found for \(peripheral.logName)")
      notifyDelegateOfError(.characteristicsNotFound, connecting: peripheral)
      return
    }

    pendingCar.readCharacteristic = readCharacteristic
    pendingCar.writeCharacteristic = writeCharacteristic

    bleVersionResolver.delegate = self
    bleVersionResolver.resolveVersion(
      with: peripheral,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )
  }

  /// Filters the given characteristics to find the characteristic the car will write to (read
  /// characteristic) and the one this device can write to (write characteristic).
  ///
  /// - Parameters:
  ///   - characteristics: The characteristics to filter.
  ///   - ioCharacteristicsUUIDs: The read/write characteristics to filter for.
  /// - Returns: A tuple containing the read and write characteristics or `nil` if either
  ///     characteristic cannot be found.
  private func filter(
    _ characteristics: [BLECharacteristic],
    for ioCharacteristicsUUIDs: IOCharacteristicsUUIDs
  ) -> (readCharacteristic: BLECharacteristic, writeCharacteristic: BLECharacteristic)? {
    guard
      let readCharacteristic = characteristics.first(where: {
        $0.uuid == ioCharacteristicsUUIDs.readUUID
      })
    else {
      Self.log.error("Cannot find read characteristic.")
      return nil
    }

    guard
      let writeCharacteristic = characteristics.first(where: {
        $0.uuid == ioCharacteristicsUUIDs.writeUUID
      })
    else {
      Self.log.error("Cannot find write characteristic.")
      return nil
    }

    return (readCharacteristic, writeCharacteristic)
  }

  private func firstPendingCar(with peripheral: BLEPeripheral) -> PendingCar? {
    return pendingCars.first(where: { $0.car === peripheral })
  }

  /// Removes all any cars in the `pendingCars` array that hold the given peripheral.
  private func removePendingCars(with peripheral: BLEPeripheral) {
    pendingCars.removeAll(where: { $0.car === peripheral })
  }

  private func notifyDelegateOfError(
    _ error: CommunicationManagerError,
    connecting peripheral: BLEPeripheral
  ) {
    cleanTimeouts(for: peripheral)
    delegate?.communicationManager(self, didEncounterError: error, whenReconnecting: peripheral)
  }

  private func cleanTimeouts(for peripheral: BLEPeripheral) {
    reconnectionTimeouts.removeValue(forKey: peripheral.identifier)?.cancel()
  }

  /// Returns a log-friendly name for the given `BLEPeripehral`.
  private func logName(for peripheral: BLEPeripheral) -> String {
    return peripheral.name ?? "no name"
  }
}

// MARK: - BLEPeripheralDelegate

extension CommunicationManager: BLEPeripheralDelegate {
  func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?) {
    guard error == nil else {
      Self.log.error(
        "Error discovering services for car (\(peripheral.logName)): \(error!.localizedDescription)"
      )
      notifyDelegateOfError(.serviceNotFound, connecting: peripheral)
      return
    }

    guard let services = peripheral.services, services.count > 0 else {
      Self.log.error("No services in car \(peripheral.logName)")
      notifyDelegateOfError(.serviceNotFound, connecting: peripheral)
      return
    }

    Self.log("Discovered \(services.count) services for car \(peripheral.logName)")

    let supportedReconnectionUUIDs = uuidConfig.supportedReconnectionUUIDs
    guard let service = services.first(where: { supportedReconnectionUUIDs.contains($0.uuid) })
    else {
      Self.log.error(
        "No service found for \(peripheral.logName) that match supported service UUIDs.")

      notifyDelegateOfError(.serviceNotFound, connecting: peripheral)
      return
    }

    peripheral.discoverCharacteristics(
      [
        Self.versionCharacteristics.writeUUID,
        Self.versionCharacteristics.readUUID,
        Self.advertisementCharacteristicUUID,
      ],
      for: service
    )
  }

  /// Prepare for transition to version resolution phase.
  private func prepareVersionResolution(
    for peripheral: BLEPeripheral,
    from service: BLEService,
    onReadyForHandshake: @escaping () -> Void
  ) {
    do {
      let helper = try reconnectionHelper(for: peripheral)
      if helper.isReadyForHandshake {
        onReadyForHandshake()
        return
      }

      // The advertisement contains data needed to make the helper ready for reconnection.
      guard
        let advertisementCharacteristic = service.characteristics?.first(where: {
          $0.uuid == Self.advertisementCharacteristicUUID
        })
      else { throw CommunicationManagerError.missingAdvertisementData }

      Self.log(
        """
        Found advertisement characteristic \(advertisementCharacteristic.uuid.uuidString) \
        on car (\(peripheral.logName)) for \
        service \(service.uuid.uuidString)
        """
      )

      helper.onReadyForHandshake = onReadyForHandshake
      peripheral.readValue(for: advertisementCharacteristic)
    } catch let error as CommunicationManagerError {
      notifyDelegateOfError(error, connecting: peripheral)
    } catch {
      notifyDelegateOfError(.unknown, connecting: peripheral)
    }
  }

  func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  ) {
    guard error == nil else {
      Self.log.error(
        """
        Error discovering characteristics for car (\(peripheral.logName)): \
        \(error!.localizedDescription)
        """
      )
      notifyDelegateOfError(.characteristicsNotFound, connecting: peripheral)
      return
    }

    guard let characteristics = service.characteristics else {
      Self.log.error("No characteristics discovered for car \(peripheral.logName)")
      notifyDelegateOfError(.characteristicsNotFound, connecting: peripheral)
      return
    }

    Self.log(
      """
      Discovered \(characteristics.count) characteristics on car (\(peripheral.logName)) for \
      service \(service.uuid.uuidString)
      """
    )

    prepareVersionResolution(for: peripheral, from: service) { [weak self] in
      self?.resolveBLEVersion(with: peripheral, characteristics: characteristics)
    }
  }

  func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    Self.log(
      """
      Received updated value for characteristic \(characteristic.uuid.uuidString) on car \
      (\(peripheral.logName))
      """
    )

    guard characteristic.uuid == Self.advertisementCharacteristicUUID else { return }

    do {
      let helper = try reconnectionHelper(for: peripheral)
      if helper.isReadyForHandshake { return }  // Nothing more to do.

      guard let advertisementData = characteristic.value else {
        Self.log.error(
          """
          The advertisement data for peripheral: (\(peripheral.logName)) was requested from \
          characteristic: \(characteristic.uuid.uuidString) but the updated value was nil.
          """
        )
        throw CommunicationManagerError.missingAdvertisementData
      }

      try helper.prepareForHandshake(withAdvertisementData: advertisementData)
    } catch let error as CommunicationManagerError {
      notifyDelegateOfError(error, connecting: peripheral)
    } catch {
      notifyDelegateOfError(.unknown, connecting: peripheral)
    }
  }

  func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral) {}
}

// MARK: - BLEVersionResolverDelegate

extension CommunicationManager: BLEVersionResolverDelegate {
  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didResolveStreamVersionTo streamVersion: MessageStreamVersion,
    securityVersionTo securityVersion: MessageSecurityVersion,
    for peripheral: BLEPeripheral
  ) {
    // This shouldn't happen because this case should have been vetted for when characteristics are
    // discovered.
    guard let pendingCar = firstPendingCar(with: peripheral) else {
      Self.log.error("No pending car for (\(peripheral.logName)) to send device id to.")
      notifyDelegateOfError(.unknown, connecting: peripheral)
      return
    }

    // This shouldn't happen because the characteristics should have been vetted already before
    // version resolution
    guard let readCharacteristic = pendingCar.readCharacteristic,
      let writeCharacteristic = pendingCar.writeCharacteristic
    else {
      Self.log.error(
        "No read or write characteristic on peripheral (\(peripheral.logName)) to send device id."
      )
      notifyDelegateOfError(.unknown, connecting: peripheral)
      return
    }

    let messageStream = BLEMessageStreamFactory.makeStream(
      version: streamVersion,
      peripheral: peripheral,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCompression: isMessageCompressionAllowed
    )

    pendingCar.messageStream = messageStream

    messageStream.delegate = self

    guard let helper = reconnectionHelpers[peripheral.identifier] else {
      notifyDelegateOfError(.unknown, connecting: peripheral)
      return
    }

    do {
      try helper.onResolvedSecurityVersion(securityVersion)
      try helper.startHandshake(messageStream: messageStream)
    } catch let error as CommunicationManagerError {
      notifyDelegateOfError(error, connecting: peripheral)
    } catch {
      notifyDelegateOfError(.unknown, connecting: peripheral)
    }
  }

  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didEncounterError error: BLEVersionResolverError,
    for peripheral: BLEPeripheral
  ) {
    switch error {
    case BLEVersionResolverError.versionNotSupported:
      notifyDelegateOfError(.versionNotSupported, connecting: peripheral)
    default:
      notifyDelegateOfError(.versionResolutionFailed, connecting: peripheral)
    }
  }
}

// MARK: - MessageStreamDelegate

extension CommunicationManager: MessageStreamDelegate {
  func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {
    guard let messageStream = messageStream as? BLEMessageStream else {
      fatalError("messageStream: \(messageStream) must be a BLEMessageStream.")
    }

    let peripheral = messageStream.peripheral

    guard let helper = reconnectionHelpers[peripheral.identifier] else {
      notifyDelegateOfError(.unknown, connecting: peripheral)
      return
    }

    // Process the handshake message. Then establish the secure channel.
    let handshakeResult = Result {
      try helper.handleMessage(messageStream: messageStream, message: message)
    }

    if case let Result.success(isHandshakeComplete) = handshakeResult, !isHandshakeComplete {
      // The handshake is incomplete, so nothing more to do until another message arrives.
      return
    }

    // The handshake is complete for this peripheral, so we need to cleanup however we return.
    defer {
      removePendingCars(with: peripheral)
    }

    // Handle any error we may have encountered in the handshake.
    if case let Result.failure(error) = handshakeResult {
      if let error = error as? CommunicationManagerError {
        notifyDelegateOfError(error, connecting: peripheral)
      } else {
        notifyDelegateOfError(.unknown, connecting: peripheral)
      }
      return
    }

    // Since the handshake is complete, we expect the helper to have a valid car id.
    guard let carId = helper.carId else {
      Self.log.error("Missing carId for peripheral (\(peripheral.logName))")
      notifyDelegateOfError(.invalidMessage, connecting: peripheral)
      return
    }

    do {
      try establishEncryption(messageStream: messageStream, carId: carId)
    } catch CommunicationManagerError.noSavedEncryption {
      notifyDelegateOfError(.noSavedEncryption, connecting: peripheral)
    } catch SecureBLEChannelError.invalidSavedSession {
      notifyDelegateOfError(.invalidSavedEncryption, connecting: peripheral)
    } catch {
      Self.log.error(
        """
        Error (\(error.localizedDescription)) establishing secure channel for peripheral
        (\(peripheral.logName))
        """
      )
      notifyDelegateOfError(.failedEncryptionEstablishment, connecting: peripheral)
    }
  }

  /// Establish a secure channel for the specified stream and car.
  ///
  ///   - Parameters:
  ///   - messageStream: The stream used to establish the secure channel.
  ///   - carId: Car identifier.
  /// - Throws: An error it fails to establish a secure channel.
  private func establishEncryption(messageStream: MessageStream, carId: String) throws {
    var reconnectionHandler = try makeChannel(messageStream: messageStream, carId: carId)
    reconnectingHandlers.append(reconnectionHandler)

    guard let messageStream = messageStream as? BLEMessageStream else {
      fatalError("messageStream: \(messageStream) must be a BLEMessageStream.")
    }

    delegate?.communicationManager(
      self,
      establishingEncryptionWith: reconnectionHandler.car,
      peripheral: messageStream.peripheral)

    reconnectionHandler.delegate = self
    try reconnectionHandler.establishEncryption()
  }

  /// Creates a secured channel with the given stream.
  ///
  /// This method will attempt to retrieve the device id out of the message and then retrieve the
  /// associated secure session with that device id.
  ///
  /// - Throws: An error if the secure session is missing.
  private func makeChannel(
    messageStream: MessageStream,
    carId: String
  ) throws -> ReconnectionHandler {
    guard let messageStream = messageStream as? BLEMessageStream else {
      fatalError("messageStream: \(messageStream) must be a BLEMessageStream.")
    }

    let peripheral = messageStream.peripheral

    guard let secureSession = secureSessionManager.secureSession(for: carId) else {
      Self.log.error(
        "No stored secure session with car \(peripheral.logName). Cannot establish encryption."
      )
      notifyDelegateOfError(.noSavedEncryption, connecting: peripheral)
      throw CommunicationManagerError.noSavedEncryption
    }

    let car = Car(id: carId, name: peripheral.name)

    return reconnectionHandlerFactory.makeHandler(
      car: car,
      connectionHandle: connectionHandle,
      secureSession: secureSession,
      messageStream: messageStream,
      secureBLEChannel: secureBLEChannelFactory.makeChannel(),
      secureSessionManager: secureSessionManager
    )
  }

  func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {
    guard let messageStream = messageStream as? BLEMessageStream else {
      fatalError("messageStream: \(messageStream) must be a BLEMessageStream.")
    }

    Self.log.error(
      "Message error \(error.localizedDescription) with car \(messageStream.peripheral.logName)."
    )

    notifyDelegateOfError(
      .invalidMessage, connecting: messageStream.peripheral)
  }

  func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {
    Self.log.error("Underlying BLEMessageStream encountered unrecoverable error. Disconnecting.")
    connectionHandle.disconnect(messageStream)
  }

  func messageStreamDidWriteMessage(_ messageStream: MessageStream, to recipient: UUID) {
    // No-op.
  }
}

// MARK: - ReconnectionHandlerDelegate

extension CommunicationManager: ReconnectionHandlerDelegate {
  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  ) {
    guard let helper = try? reconnectionHelper(for: reconnectionHandler.peripheral) else {
      Self.log.error("Missing reconnection helper after establishing secure channel.")
      delegate?.communicationManager(
        self,
        didEncounterError: .missingReconnectionHelper(reconnectionHandler.peripheral.identifier),
        whenReconnecting: reconnectionHandler.peripheral
      )
      return
    }

    helper.configureSecureChannel(
      securedCarChannel,
      using: connectionHandle
    ) { [weak self] success in
      guard let self = self else { return }

      guard success else {
        self.delegate?.communicationManager(
          self,
          didEncounterError: .configureSecureChannelFailed,
          whenReconnecting: reconnectionHandler.peripheral)
        return
      }

      self.cleanTimeouts(for: reconnectionHandler.peripheral)

      self.delegate?.communicationManager(self, didEstablishSecureChannel: securedCarChannel)
      self.reconnectingHandlers.removeAll(where: { $0.car == securedCarChannel.car })

      self.reconnectionHelpers[reconnectionHandler.peripheral.identifier] = nil
    }
  }

  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEncounterError error: ReconnectionHandlerError
  ) {
    // This call to notify delegates will clean up any reconnection timeouts.
    notifyDelegateOfError(
      .failedEncryptionEstablishment,
      connecting: reconnectionHandler.peripheral
    )
    reconnectingHandlers.removeAll(where: { $0.car == reconnectionHandler.car })
    reconnectionHelpers[reconnectionHandler.peripheral.identifier] = nil
  }
}

// MARK: - Overlay Extensions

extension Overlay {
  /// Indicates whether message compression is allowed.
  var isMessageCompressionAllowed: Bool {
    // Allow for message compression unless the overlay vetoes it.
    self[CommunicationManager.messageCompressionAllowedKey] as? Bool ?? true
  }
}
