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

@_implementationOnly import AndroidAutoConnectedDeviceTransport
@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import AndroidAutoLogger
@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation

/// Delegate that will be notified of the status of association.
@MainActor public protocol ConnectionManagerAssociationDelegate: AnyObject {
  /// Invoked when a car has been discovered and is available for association.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager that is managing connections.
  ///   - car: A car that the current device can be associated with.
  ///   - adverstisedName: An optional name that the car is currently using to identify
  ///       itself to the user and should be shown to the user. This name will not necessarily
  ///       match the name in `car.name`.
  func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didDiscover car: AnyPeripheral,
    advertisedName: String?)

  /// Invoked when a connection is successfully created with a peripheral.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager who is managing connections.
  ///   - peripheral: The peripheral that has been connected to.
  func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didConnect peripheral: AnyPeripheral
  )

  /// Invoked when the connection manager has finished the association of a device.
  ///
  /// - Parameters
  ///   - connectionManager: The connection manager that finished association.
  ///   - car: The car that completed association.
  func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didCompleteAssociationWithCar car: Car
  )

  /// Invoked when the connection manager requires the given pairing code to be displayed to the
  /// user so they can confirm that it matches the value on the car being associated.
  ///
  /// The pairing code should be displayed to the user on the current device.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager handling association.
  ///   - pairingCode: The pairing code to display.
  func connectionManager(
    _ connectionManager: AnyConnectionManager,
    requiresDisplayOf pairingCode: String
  )

  /// Invoked when the connection manager has encountered an error during the association process.
  ///
  /// - Parameters:
  ///   - connectionManager: The connection manager handling association.
  ///   - error: The error that occurred. It will be of type `AssociationError`.
  func connectionManager(_ connectionManager: AnyConnectionManager, didEncounterError error: Error)
}

/// The possible errors from a call to `associate()`.
enum StartAssociationError: Error {
  /// The internal state of ConnectionManager is not ready for association.
  case stateNotReady
}

/// Heterogeneous protocol adopted by a connection manager
@MainActor public protocol AnyConnectionManager {
}

/// Homogeneous protocol adopted by a connection manager for type specific extensions.
@MainActor protocol SomeConnectionManager {
  associatedtype Peripheral

  func peripheral(from channel: SecuredCarChannel) -> Peripheral?
  func peripheral(from messageStream: MessageStream) -> Peripheral?
  func peripheral(from blePeripheral: BLEPeripheral) -> Peripheral?
}

// MARK: - ConnectionHandle

/// Manages connection status of various endpoints connected to a remote car.
@MainActor protocol ConnectionHandle {
  /// Disconnects the specified `MessageStream` from its remote car.
  func disconnect(_ messageStream: MessageStream)

  /// Request the user role (driver/passenger) for the specified channel.
  func requestConfiguration(
    for channel: SecuredConnectedDeviceChannel,
    completion: @escaping () -> Void
  )
}

/// Log used internally by `ConnectionManager` since Generics can't have static
/// stored properties.

private let plistFileName = "connected_device_manager"

/// The length in bytes of the advertisement data that indicates whether the value should be
/// converted to a string via UTF-8 encoding.
///
/// If the length does not match, then the data should be converted to a hexadecimal representation.
private let advertisementLengthForUTF8Conversion = 8

private let signpostMetrics = SignpostMetrics(category: "ConnectionManager")

private enum ConnectionManagerSignposts {
  static let associationDuration = SignpostDuration("Association Duration")
  static let associationCompletion = SignpostMarker("Association Completion")
  static let associationFailure = SignpostMarker("Association Failure")
  static let reconnectionDuration = SignpostDuration("Reconnection Duration")
  static let reconnectionCompletion = SignpostMarker("Reconnection Completion")
  static let reconnectionFailure = SignpostMarker("Reconnection Failure")
}

extension BuildNumber {
  /// The version of this SDK.
  fileprivate static let sdkVersion = BuildNumber(major: 3, minor: 1, patch: 0)
}

/// Holds all the necessary information to try a reconnection for a `Peripheral`.
private struct ConnectionRetryState {
  /// The block of code that will attempt a connection retry.
  let retryHandler: DispatchWorkItem

  /// The number of times that a connection has been retried for a given `Peripheral`.
  var retryCount = 0
}

/// A `ConnectionManager` that utilizes Core Bluetooth for establishing and maintaining connections
/// with a remote vehicle.
///
/// This manager scans for specific UUIDs to associate a car and to reconnect. The UUIDs for these
/// operations can be configured via a `connected_device_manager.plist` file and the following
/// four key values:
///
/// - `AssociationServiceUUID`
/// - `AssociationDataUUID`
/// - `ReconnectionServiceUUID`
/// - `ReconnectionDataUUID`
///
/// These keys should map to a UUID in string form: "00000000-0000-0000-0000-000000000000". For
/// example:
///
/// ```
/// <key>AssociationServiceUUID</key>
/// <string>00000000-0000-0000-0000-000000000000</string>
/// ```
///
/// If a file is not specified, there are default values for these UUIDs provided by this manager.
/// However, it is recommended that the user configure these to be unique to their application.
/// Simply generating random UUIDs for these values should be sufficient for uniqueness as UUID
/// collisions are statistically impossible.
@MainActor public class CoreBluetoothConnectionManager: ConnectionManager<CBCentralManager> {
  /// The time after which a connection is retried.
  ///
  /// See `maxConnectionRetryCount` for an explanation of why these intervals are
  /// needed.
  ///
  /// The length of this array should match `maxConnectionRetryCount`.
  private static let retryTimeIntervals: [DispatchTimeInterval] = [.seconds(2), .seconds(4)]

  /// The maximum amount of times a call to `connect` will be retried.
  ///
  /// When a phone and car are paired via Bluetooth, a call to connect the two via BLE
  /// will oftentimes not result in a `didConnect` call. However, if we retry after a certain amount
  /// of time, then this connection can succeed.
  ///
  /// There is no method to obtain if the car is currently paired via Bluetooth, so need to opt
  /// for retrying.
  ///
  /// From observations, usually a retry of one time is all that's required. After this limit is
  /// reached, the connection attempt is torn down and a re-scan is initiated.
  private static let maxConnectionRetryCount = retryTimeIntervals.count

  /// A mapping of `Peripheral` identifiers to the current state of connection retry.
  ///
  /// Any peripherals that are attempting connection will be in this map and they will be removed
  /// upon connection.
  private var connectionRetryStates: [UUID: ConnectionRetryState] = [:]

  private let centralManagerWrapper: CoreBluetoothCentralManagerWrapper

  public override init() {
    centralManagerWrapper = CoreBluetoothCentralManagerWrapper()
    super.init(
      centralManager: centralManagerWrapper.centralManager,
      associatedCarsManager: UserDefaultsAssociatedCarsManager(),
      reconnectionHelperFactory: ReconnectionHelperFactoryImpl.self
    )
    centralManagerWrapper.connectionManager = self
  }

  /// Connects to the given `peripheral` and schedules retry events if necessary.
  override func connect(with peripheral: Peripheral) {
    resetConnectionRetryState(for: peripheral)

    centralManager.connect(peripheral, options: nil)

    // After a connection call has been made, schedule a retry to call `connect` again if we do
    // not receive a `didConnect` callback.
    let retryHandler = DispatchWorkItem { [weak self] in
      self?.handleConnectionRetry(with: peripheral)
    }

    let retryState = ConnectionRetryState(retryHandler: retryHandler)
    connectionRetryStates[peripheral.identifier] = retryState

    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.retryTimeIntervals[retryState.retryCount],
      execute: retryHandler
    )
  }

  /// Attempts a connect with the given peripheral and schedules a handler to retry the connection
  /// after a certain amount of time has passed.
  private func handleConnectionRetry(with peripheral: Peripheral) {
    guard var retryState = connectionRetryStates[peripheral.identifier] else {
      log(
        """
        Attempt to handle connection retry for car (\(peripheral.logName)), \
        but no retry state exists. Disconnecting.
        """
      )
      disconnect(peripheral)
      return
    }

    guard retryState.retryCount < Self.maxConnectionRetryCount else {
      log(
        """
        Attempted to retry connection with car (\(peripheral.logName)), \
        but max retry limit reached. Disconnecting
        """
      )
      disconnect(peripheral)
      resetConnectionRetryState(for: peripheral)
      return
    }

    guard peripheral.state != .connected else {
      log(
        """
        Car (\(peripheral.logName)) connected (\(peripheral.state.rawValue)). \
        No need to schedule a connection retry
        """
      )

      resetConnectionRetryState(for: peripheral)
      return
    }

    log(
      "Retrying connection with car (\(peripheral.logName)). Attempt \(retryState.retryCount + 1)")

    centralManager.connect(peripheral, options: nil)

    DispatchQueue.main.asyncAfter(
      deadline: .now() + Self.retryTimeIntervals[retryState.retryCount],
      execute: retryState.retryHandler
    )

    retryState.retryCount += 1
    connectionRetryStates[peripheral.identifier] = retryState
  }

  override fileprivate func resolveError(_ error: NSError) -> Error {
    guard #available(iOS 13.4, watchOS 6.4, *) else { return error }
    guard isAssociating else { return error }

    switch error.code {
    case CBError.peerRemovedPairingInformation.rawValue where error.domain == CBErrorDomain:
      return AssociationError.peerRemovedPairingInfo
    default:
      return super.resolveError(error)
    }
  }

  override func onPeripheralConnected(_ peripheral: Peripheral) {
    log(
      "Connected car (\(peripheral.logName))",
      metadata: ["car": peripheral.logName, "connected": true]
    )
    resetConnectionRetryState(for: peripheral)
  }

  override func onPeripheralConnectionFailed(_ peripheral: Peripheral, error: NSError) {
    log.error("Connection to: \(peripheral.logName) failed due to error: \(error)")
    resetConnectionRetryState(for: peripheral)
  }

  override func onPeripheralDisconnected(_ peripheral: Peripheral) {
    log(
      "Disconnected car (\(peripheral.logName))",
      metadata: ["car": peripheral.logName, "connected": false]
    )
    resetConnectionRetryState(for: peripheral)
  }

  private func resetConnectionRetryState(for peripheral: Peripheral) {
    connectionRetryStates.removeValue(forKey: peripheral.identifier)?.retryHandler.cancel()
  }

  override func peripheral(from channel: SecuredCarChannel) -> Peripheral? {
    guard let bleChannel = channel as? SecuredCarChannelPeripheral else { return nil }
    guard let blePeripheral = bleChannel.peripheral as? BLEPeripheral else { return nil }
    return peripheral(from: blePeripheral)
  }

  override func peripheral(from messageStream: MessageStream) -> Peripheral? {
    guard let messageStream = messageStream as? BLEMessageStream else { return nil }
    return peripheral(from: messageStream.peripheral)
  }

  override func peripheral(from blePeripheral: BLEPeripheral) -> Peripheral? {
    guard let wrapper = blePeripheral as? CBPeripheralWrapper else { return nil }
    return wrapper.peripheral
  }

  override func registerServiceObserver(on channel: SecuredCarChannel) {
    guard let bleChannel = channel as? SecuredCarChannelPeripheral,
      let wrapper = bleChannel.peripheral as? CBPeripheralWrapper
    else {
      return
    }

    wrapper.observeServiceModifications { [weak self] _, invalidatedServices in
      self?.inspectServices(invalidatedServices, on: channel.car)
    }
  }

  override func associate(peripheral: Peripheral) {
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.associationDuration.begin)
    let peripheralWrapper = CBPeripheralWrapper(peripheral: peripheral)
    associationManager.associate(peripheralWrapper, config: associationConfig)
  }

  override func setupSecureChannel(with peripheral: Peripheral) {
    do {
      try communicationManager.setUpSecureChannel(
        with: CBPeripheralWrapper(peripheral: peripheral),
        id: peripheralDeviceIds[peripheral.identifier]
      )
    } catch CommunicationManagerError.notAssociated {
      log.error(
        """
        Unexpected. Attempted to establish a secure channel with an \
        unassociated device: \(peripheral.logName)
        """
      )
    } catch CommunicationManagerError.noSavedEncryption {
      log.error("No saved encryption session information for device: \(peripheral.logName).")
    } catch {
      log.error("Unknown error during establishment of secure channel.")
    }
  }
}

/// Listens to and manages state changes on the bluetooth stack.
@MainActor public class ConnectionManager<CentralManager>:
  NSObject,
  SomeConnectionManager,
  AnyConnectionManager
where CentralManager: SomeCentralManager {
  public typealias Peripheral = CentralManager.Peripheral

  fileprivate lazy var log = Logger(for: type(of: self))

  fileprivate var centralManager: CentralManager

  fileprivate let reconnectionHelperFactory: ReconnectionHelperFactory.Type

  // Note: need to declare these as optional because init() needs to be called first before
  // "self" can be used in constructor.
  fileprivate var communicationManager: CommunicationManager!
  fileprivate var associationManager: AssociationManager!

  fileprivate let associatedCarsManager: AssociatedCarsManager

  private let plistLoader = PListLoaderImpl(plistFileName: plistFileName)

  private let uuidConfig: UUIDConfig

  /// A value to add as as prefix to any cars that are discovered for association.
  private var associationNamePrefix = ""

  var discoveredPeripherals: Set<Peripheral> = []

  /// Whether the connection manager is currently associating with a car.
  fileprivate var isAssociating = false

  /// A default association configuration whose values may be overridden by the user.
  fileprivate var defaultAssociationConfig: AssociationConfig

  /// The current configuration for an association scan.
  fileprivate var associationConfig: AssociationConfig

  /// Restricting filter applied to the advertised name for considering a discovered peripheral for
  /// association.
  ///
  /// This filter is intended for internal use.
  ///
  /// If this filter is `nil` then every discovered car will be considered a valid candidate
  /// regardless of its advertised name.
  ///
  /// This closure takes the discovered car's advertised name as the parameter and should return
  /// `true` to accept the car and `false` to ignore the car.
  fileprivate var associationAdvertisedNameFilter: ((String?) -> Bool)? = nil

  /// The possible events within the connection manager that can be observed.
  ///
  /// Each observable event is a mapping of a unique id to a closure function that is executed when
  /// that state changes.
  fileprivate var observations = (
    state: [UUID: (ConnectedCarManager, RadioState) -> Void](),
    connected: [UUID: (ConnectedCarManager, Car) -> Void](),
    securedChannel: [UUID: (ConnectedCarManager, SecuredCarChannel) -> Void](),
    disconnected: [UUID: (ConnectedCarManager, Car) -> Void](),
    dissociation: [UUID: (ConnectedCarManager, Car) -> Void]()
  )

  /// Actions to perform sequentially once the power state has been determined.
  private var pendingPowerStateActions: [(RadioState) -> Void] = []

  /// Maps `Peripheral`s by their identifier to its associated device ID.
  ///
  /// The device ID is different than the `identifier` in the `Peripheral`. During association and
  /// reconnection, the device ID will be sent by the peripheral to this phone.
  ///
  /// Depending on the version of communication, the device ID will either be part of the
  /// advertisement data of the peripheral or sent after connection.
  fileprivate var peripheralDeviceIds: [UUID: String] = [:]

  /// Central out of band association token provider which wraps others.
  private lazy var centralOutOfBandAssociationTokenProvider:
    CoalescingOutOfBandTokenProvider<AnyOutOfBandTokenProvider> =
      makeCentralOutOfBandTokenProvider()

  /// Out of band association token provider which is externally populated.
  private let externalAssociationTokenProvider = PassiveOutOfBandTokenProvider()

  public weak var associationDelegate: ConnectionManagerAssociationDelegate?

  /// The current state of bluetooth.
  public var state: RadioState = CBManagerState.unknown

  public fileprivate(set) var securedChannels: [SecuredCarChannel] = []
  let secureSessionManager: SecureSessionManager = KeychainSecureSessionManager()

  fileprivate var systemFeatureManager: SystemFeatureManager!

  /// Returns `true` if the current device has been associated with a car.
  public var isAssociated: Bool {
    return associationManager.isAssociated
  }

  /// The cars that this device is currently associated with. Empty if the device is not currently
  /// associated with a car.
  public var associatedCars: Set<Car> {
    return associatedCarsManager.cars
  }

  /// The number of cars that have been associated.
  public var associatedCarCount: Int {
    return associatedCarsManager.count
  }

  public override init() {
    fatalError("ConnectionManager should not be created. Utilize a subclass instead.")
  }

  init(
    centralManager: CentralManager,
    associatedCarsManager: AssociatedCarsManager,
    reconnectionHelperFactory: ReconnectionHelperFactory.Type
  ) {
    self.reconnectionHelperFactory = reconnectionHelperFactory
    self.centralManager = centralManager
    self.associatedCarsManager = associatedCarsManager
    let bleVersionResolver = BLEVersionResolverImpl()
    let secureBLEChannelFactory = UKey2ChannelFactory()

    uuidConfig = UUIDConfig(plistLoader: plistLoader)
    defaultAssociationConfig = AssociationConfig(associationUUID: uuidConfig.associationUUID)
    associationConfig = defaultAssociationConfig

    // Calling `super` here so that subsequent code can use `self`.
    super.init()

    log("SDK Version: \(BuildNumber.sdkVersion)")

    let connectionHandleProxy = ConnectionHandleProxy(connectionManager: self)
    let overlay = plistLoader.loadOverlayValues()
    systemFeatureManager = SystemFeatureManager(connectedCarManager: self)

    associationManager = AssociationManager(
      overlay: overlay,
      connectionHandle: connectionHandleProxy,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManager,
      secureSessionManager: secureSessionManager,
      secureBLEChannel: secureBLEChannelFactory.makeChannel(),
      bleVersionResolver: bleVersionResolver,
      outOfBandTokenProvider: centralOutOfBandAssociationTokenProvider
    )

    communicationManager = CommunicationManager(
      overlay: overlay,
      connectionHandle: connectionHandleProxy,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManager,
      secureSessionManager: secureSessionManager,
      secureBLEChannelFactory: secureBLEChannelFactory,
      bleVersionResolver: bleVersionResolver,
      reconnectionHandlerFactory: self
    )

    state = centralManager.state

    associationManager.delegate = self
    communicationManager.delegate = self

    if isAssociated {
      connectToAssociatedCars()
    }
  }

  /// Initiates a scan for nearby cars that the current device can be associated with.
  ///
  /// The `configurator` closure will be utilized to adjust various properties of the scan if
  /// provided. It will be passed a default configuration that is prefilled with information
  /// specified by `connected_device_manager.plist`. Callers should modify the passed object to '
  /// override any items and produce a new config. Refer to the documentation of `AssociationConfig`
  /// for details on configuration possibilities.
  ///
  /// A class can be notified of the results of this scan by registering as a
  /// `ConnectionManagerAssociationDelegate`. The given `namePrefix` may be added to the beginning
  /// of the names of cars that are found. This API will only add the prefix when doing so matches
  /// the advertisement name the car is currently displaying.
  ///
  /// When this method is called, any scans for associated cars will stop. Ensure an explicit call
  /// to `connectToAssociatedCars()` is invoked to resume connecting to associated cars. After an
  /// association flow is complete, connecting to associated cars will resume automatically.
  ///
  /// This call will scan for the default UUID for reconnection unless an overlay is provided in a
  /// `connected_device_manager.plist` file. To overlay this value, create the file and add an
  /// entry with a key of `AssociationServiceUUID`. The value of this key should be a 16-byte
  /// UUID of the form `00000000-0000-0000-0000-000000000000`.
  ///
  /// Typically, call this method with a readyState of zero when you know the device is in a ready
  /// state (e.g. bluetooth power is on). If this is being called from an app launch, the device may
  /// not yet be ready, so you can request association to begin within the specified timeout once
  /// the device is ready. By calling this method before the device is ready, the connection manager
  /// is configured for association which allows the UI to query the configuration (e.g. that an out
  /// of band token is being used for association at launch).
  ///
  /// - Parameters:
  ///   - namePrefix: A value that may be prefixed to the name of cars that are discovered.
  ///   - outOfBandSource: Source of out of band data.
  ///   - configurator: Closure allowing for custom configuration of association parameters.
  public func scanForCarsToAssociate(
    namePrefix: String = "",
    outOfBandSource: OutOfBandAssociationDataSource? = nil,
    configurator: ((inout AssociationConfig) -> Void)? = nil
  ) {
    associationNamePrefix = namePrefix

    // Prefill out the configuration object for callers to modify.
    associationConfig = defaultAssociationConfig
    configurator?(&associationConfig)

    if let outOfBandSource = outOfBandSource {
      externalAssociationTokenProvider.postToken(outOfBandSource.token)
      associationAdvertisedNameFilter = {
        guard let advertisedName = $0 else { return false }
        return advertisedName.compare(
          outOfBandSource.deviceID.hex, options: .caseInsensitive) == .orderedSame
      }
    } else {
      associationAdvertisedNameFilter = nil
    }

    // A scan for peripherals will override any previous scans. Thus, as soon as we start scanning
    // for cars to associate, it is considered in the association flow.
    isAssociating = true

    // Clear all previously discovered peripherals since a new scan is starting.
    discoveredPeripherals = []

    guard centralManager.state.isPoweredOn else {
      isAssociating = false
      externalAssociationTokenProvider.reset()
      log.error(
        """
        Request to scan for cars to associate, but Bluetooth is not on. \
        State: \(centralManager.state.rawValue).
        """
      )
      return
    }

    let associationUUID = associationConfig.associationUUID
    log("Starting scan for cars to associate with UUID \(associationUUID)")

    centralManager.scanForPeripherals(
      withServices: [associationUUID],
      options: nil
    )
  }

  /// Schedules the requested action to be performed when the radio state becomes known.
  ///
  /// On startup, the radio power state is unknown, and there is a race between requests that
  /// depend on the known radio power state and the power state being determined. This method
  /// performs the requested action when the power state becomes known. If the power state is
  /// already known at the time of the call, the requested action is performed immediately.
  ///
  /// The action is passed the power state (e.g. powered on, off).
  ///
  /// - Parameter action: Action to perform when the power state becomes known.
  public func requestRadioStateAction(_ action: @escaping (RadioState) -> Void) {
    if state.isUnknown {
      log("Power state is unknown, pending requested action.")
      pendingPowerStateActions.append(action)
    } else {
      action(state)
    }
  }

  /// Determines whether an `outOfBandSource` matches the ongoing association scan data.
  ///
  /// This method will help determine if the given out of band data is the same as an ongoing scan.
  /// The return value will change after
  /// `scanForCarsToAssociate(namePreix:outOfBandSource:configurator:)` is called.
  ///
  /// - Parameter outOfBandSource: The data which will be compared with ongoing scan data.
  /// - Returns: `true` if the `outOfBandSource` matches the data of an ongoing scan.
  public func matchesOngoingScanDataSource(outOfBandSource: OutOfBandAssociationDataSource)
    -> Bool
  {
    return associationAdvertisedNameFilter?(outOfBandSource.deviceID.hex) ?? false
  }

  /// Attempts to connect to any cars that are already associated.
  ///
  /// This call will scan for the default UUID for reconnection unless an overlay is provided in a
  /// `connected_device_manager.plist` file. To overlay this value, create the file and add an
  /// entry with a key of `ReconnectionServiceUUID`. The value of this key should be a 16-byte
  /// UUID of the form `00000000-0000-0000-0000-000000000000`.
  ///
  /// To be notified of connection events, register as an observer with the
  /// `observeConnection(using:)` method.
  public func connectToAssociatedCars() {
    isAssociating = false

    // No need to scan if there are no cars that are associated.
    if associationManager.cars.isEmpty {
      log("Request to connect to associated cars, but none associated. Will not scan.")
      return
    }

    guard centralManager.state == .poweredOn else {
      log.error(
        """
        Request to scan for associated cars, but bt is not on. \
        State: \(centralManager.state.rawValue).
        """
      )
      return
    }

    log("Starting scan for associated cars.")

    // If this scan completes, then any associated cars are automatically connected to.
    centralManager.scanForPeripherals(
      withServices: uuidConfig.supportedReconnectionUUIDs,
      options: nil
    )
  }

  /// Determine whether there is a secure connection with the car having the specified id.
  ///
  /// - Parameter car: The car for which to check for the secure connection.
  /// - Returns: `true` if the car is connected securely.
  public func isCarConnectedSecurely(_ car: Car) -> Bool {
    return securedChannels.contains { $0.car.id == car.id }
  }

  /// Cancels any current scans.
  public func stopScanning() {
    centralManager.stopScan()
  }

  /// Begins the association process with the given car.
  ///
  /// The caller should add itself as a `ConnectionManagerAssociationDelegate` to be
  /// notified of the progress of this association.
  ///
  /// - Parameter car: the car to associate.
  /// - Throws: An error if a passcode is required, but is not set.
  public func associate(_ car: Peripheral) throws {
    guard state.isPoweredOn else {
      throw StartAssociationError.stateNotReady
    }

    log("Attempting to connect to (\(car.logName)) for association")

    isAssociating = true

    connect(with: car)
  }

  /// Cancels an association request if one has been started already.
  public func clearCurrentAssociation() {
    if centralManager.isScanning {
      centralManager.stopScan()
    }

    associationManager.clearCurrentAssociation()
    disconnectAllPeripherals()

    // Since the current association attempt is cleared, we can resume searches for associated
    // cars.
    connectToAssociatedCars()
  }

  /// Cancels an association request if one has been started already and clears association
  /// with all previously associated cars.
  public func clearAllAssociations() {
    if centralManager.isScanning {
      centralManager.stopScan()
    }

    associationManager.cars.forEach { car in
      observations.dissociation.values.forEach { observation in
        observation(self, car)
      }
    }

    associationManager.clearAllAssociations()
    disconnectAllPeripherals()
  }

  /// Clears the association for the specified car.
  ///
  /// - Parameter car: The car to be removed.
  public func clearAssociation(for car: Car) {
    log("Clearing association for car id = \(car.id)")

    disconnect(car)

    associationManager.clearAssociation(for: car)

    observations.dissociation.values.forEach { observation in
      observation(self, car)
    }
  }

  /// Renames an associated car.
  ///
  /// The given name should be a non-empty string. If the string given is empty, then the name will
  /// be ignored.
  ///
  /// - Parameters:
  ///   - carId: The ID of the car to rename.
  ///   - name: The new name for the car.
  /// - Returns: `true` if the name was changed successfully.
  public func renameCar(withId carId: String, to name: String) -> Bool {
    if name.isEmpty {
      return false
    }
    return associationManager.renameCar(withId: carId, to: name)
  }

  /// Make the central out of band token provider which coalesces registed token providers.
  ///
  /// The central token provider can register any out of band token provider. It is initialized
  /// with the external token provider and if supported will also register the accessory oob token
  /// provider.
  ///
  /// - Returns: The new out of band token provider.
  private func makeCentralOutOfBandTokenProvider()
    -> CoalescingOutOfBandTokenProvider<AnyOutOfBandTokenProvider>
  {
    CoalescingOutOfBandTokenProvider {
      $0.register(wrapping: externalAssociationTokenProvider)
      let accessoryOutOfBandTokenProviderFactory = AccessoryOutOfBandTokenProviderFactory()
      guard
        let accessoryOutOfBandTokenProvider =
          accessoryOutOfBandTokenProviderFactory.makeProvider()
      else {
        log("SPP Out of Band token provider is unavailable.")
        return
      }
      log("Registered SPP Out of Band token provider.")
      $0.register(wrapping: accessoryOutOfBandTokenProvider)
    }
  }

  /// Verifies that the list of now invalidated services does not include the services that this
  /// manager needs to connect.
  ///
  /// If it does, then this manager will disconnect from the given `Car` as messages are no longer
  /// able to be sent and received.
  fileprivate func inspectServices(_ invalidatedServices: [BLEService], on car: Car) {
    log("Car (\(car.logName)) has invalidated services: \(invalidatedServices.map{$0.uuid})")

    if let serviceID = invalidatedServices.lazy.map({ $0.uuid.uuidString }).first(where: {
      if $0 == associationConfig.associationUUID.uuidString {
        return true
      } else if areAnySecuredCarChannelsInvalid(car) {
        return true
      } else {
        return false
      }
    }) {
      log(
        """
        Required service \(serviceID) invalidated for car \
        (\(car.logName)). Disconnecting if currently connected.
        """
      )

      disconnect(car)
    }
  }

  /// Determines whether the specified car's secured channels are valid.
  private func areAnySecuredCarChannelsInvalid(_ car: Car) -> Bool {
    securedChannels.filter { $0.car.id == car.id }.lazy
      .contains {
        return !$0.isValid
      }
  }

  /// Attempts to disconnect the given car if it is currently connected.
  private func disconnect(_ car: Car) {
    let connectedChannels = securedChannels.filter { $0.car.id == car.id }
    connectedChannels.forEach { channel in
      if let peripheral = peripheral(from: channel) {
        log("peripheral state: \(peripheral.state)")
        disconnect(peripheral)
      }
    }
  }

  /// Disconnects the given `BLEMessageStream` if it is currently connected.
  func disconnect(_ messageStream: MessageStream) {
    if let peripheral = peripheral(from: messageStream) {
      disconnect(peripheral)
    }
  }

  /// Disconnect the given peripheral if it is currently connected or connecting.
  func disconnect(_ peripheral: Peripheral) {
    log("Request to disconnect peripheral: \(peripheral.logName)")

    // If the peripheral is already disconnected, then calling `cancelPeripheralConnection` will
    // result in nothing happening. So, if this manager believes the device is connected, then
    // manually send out a disconnection event.
    if peripheral.state == .disconnected,
      discoveredPeripherals.contains(where: { $0 == peripheral })
    {
      log(
        """
        Peripheral (\(peripheral.logName)) already in disconnected \
        state (\(peripheral.state.rawValue)). Manually handling disconnecting.
        """
      )

      handleDisconnection(of: peripheral, error: nil)
      return
    }

    centralManager.cancelPeripheralConnection(peripheral)
  }

  private func disconnectAllPeripherals() {
    log("Request to disconnect all peripherals. Peripheral count: \(discoveredPeripherals.count)")

    discoveredPeripherals.forEach { disconnect($0) }
  }

  fileprivate func resolveError(_ error: NSError) -> Error {
    return isAssociating ? AssociationError.unknown : error
  }

  // MARK: - ConnectionManager methods to be overridden

  // TODO(b/152079838): Extend testability to other classes to make override unnecessary in the
  // following methods.

  /// Subclasses should override this method to connect to the given peripheral.
  func connect(with peripheral: Peripheral) {}

  /// Subclasses should override this method to perform any clean up tasks needed when the
  /// given `peripheral` has connected.
  func onPeripheralConnected(_ peripheral: Peripheral) {}

  /// Subclasses should override this method to perform any clean up tasks needed when the
  /// given `peripheral` connection has failed.
  func onPeripheralConnectionFailed(_ peripheral: Peripheral, error: NSError) {}

  /// Subclasses should override this method to perform any clean up tasks needed when the
  /// given `peripheral` has disconnected.
  func onPeripheralDisconnected(_ peripheral: Peripheral) {}

  /// Subclasses should override this method to register any listeners they want on the service
  /// changes within the given channel.
  func registerServiceObserver(on channel: SecuredCarChannel) {}

  /// Subclasses should override this method to implement peripheral association by
  /// associating the peripheral with the `associationManager`.
  func associate(peripheral: Peripheral) {}

  /// Subclasses should override this method to setup a secure channel with the specified
  /// peripheral using `communicationManager`.
  func setupSecureChannel(with peripheral: Peripheral) {}

  /// Subclasses should override this method to get the specified channel's peripheral.
  func peripheral(from channel: SecuredCarChannel) -> Peripheral? {
    return nil
  }

  /// Subclasses should override this method to retrieve the specified stream's peripheral.
  func peripheral(from messageStream: MessageStream) -> Peripheral? {
    return nil
  }

  /// Subclasses should override this method to retrieve the peripheral from a `BLEPeripheral`.
  func peripheral(from blePeripheral: BLEPeripheral) -> Peripheral? {
    return nil
  }

  /// Request the user role (driver/passenger) for the specified channel.
  func requestConfiguration(
    for channel: SecuredConnectedDeviceChannel,
    completion: @escaping () -> Void
  ) {
    log("Requesting configuration of channel: \(channel)")
    channel.configure(using: systemFeatureManager) { [weak self] channel in
      defer { completion() }
      guard let self = self else { return }
      self.log("Secure channel configuration complete.")
    }
  }
}

// MARK: - ConnectionHandleProxy

/// Wrapper around a `ConnectionManager` so that it can be passed without having to worry about
/// object reference retention.
@MainActor private struct ConnectionHandleProxy<T: SomeCentralManager>: ConnectionHandle {
  private unowned let connectionManager: ConnectionManager<T>

  init(connectionManager: ConnectionManager<T>) {
    self.connectionManager = connectionManager
  }

  func disconnect(_ messageStream: MessageStream) {
    connectionManager.disconnect(messageStream)
  }

  func requestConfiguration(
    for channel: SecuredConnectedDeviceChannel,
    completion: @escaping () -> Void
  ) {
    connectionManager.requestConfiguration(for: channel, completion: completion)
  }
}

// MARK: - Observers for event changes

extension ConnectionManager: ConnectedCarManager {
  public func securedChannel(for car: Car) -> SecuredCarChannel? {
    return securedChannels.first(where: { $0.car.id == car.id })
  }

  /// Observe when the `state` of the connection manager has changed.
  @discardableResult
  public func observeStateChange(
    using observation: @escaping (ConnectedCarManager, RadioState) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.state[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.state.removeValue(forKey: id)
    }
  }

  /// Observe when a device has been connected to this manager.
  @discardableResult
  public func observeConnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.connected[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.connected.removeValue(forKey: id)
    }
  }

  /// Observe when a secure channel has been set up with a given device.
  @discardableResult
  public func observeSecureChannelSetUp(
    using observation: @escaping (ConnectedCarManager, SecuredCarChannel) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.securedChannel[id] = observation

    // When first called, notify the observer of all existing secure channels.
    securedChannels.forEach { observation(self, $0) }

    return ObservationHandle { [weak self] in
      self?.observations.securedChannel.removeValue(forKey: id)
    }
  }

  /// Observe when a device has been disconnected from this manager.
  @discardableResult
  public func observeDisconnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.disconnected[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.disconnected.removeValue(forKey: id)
    }
  }

  /// Observe when a car has been dissociated from this manager.
  @discardableResult
  public func observeDissociation(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.dissociation[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.dissociation.removeValue(forKey: id)
    }
  }
}

// MARK: - CommunicationManagerDelegate

/// A delegate to be notified of the current state of secure communication establishment.
extension ConnectionManager: CommunicationManagerDelegate {
  func communicationManager(
    _ communicationManager: CommunicationManager,
    establishingEncryptionWith car: Car,
    peripheral: BLEPeripheral
  ) {
    // Ensure that the list of peripherals to device ids is up to date.
    peripheralDeviceIds[peripheral.identifier] = car.id

    observations.connected.values.forEach { observation in
      observation(self, car)
    }
  }

  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  ) {
    self.securedChannels.append(securedCarChannel)
    self.registerServiceObserver(on: securedCarChannel)

    self.observations.securedChannel.values.forEach { observation in
      observation(self, securedCarChannel)
    }
  }

  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEncounterError error: CommunicationManagerError,
    whenReconnecting peripheral: BLEPeripheral
  ) {
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.reconnectionFailure)
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.reconnectionDuration.end)
    log.error(
      "Encountered error during reconnection. Disconnecting peripheral: \(peripheral.logName).")

    guard let somePeripheral = self.peripheral(from: peripheral) else {
      log.error(
        "Peripheral could not be mapped to a peripheral type this connection manager knows.")
      return
    }

    // TODO(b/182992203): Check the error (e.g. noSavedEncryption or invalidSavedEncryption) to see
    // if we should create and save a new encryption session.

    disconnect(somePeripheral)
  }
}

// MARK: - AssociationManagerDelegate

extension ConnectionManager: AssociationManagerDelegate {
  func associationManager(
    _ associationManager: AssociationManager,
    didCompleteAssociationWithCar car: Car,
    securedCarChannel: SecuredConnectedDeviceChannel,
    peripheral: BLEPeripheral
  ) {
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.associationDuration.end)
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.associationCompletion)

    self.securedChannels.append(securedCarChannel)
    self.registerServiceObserver(on: securedCarChannel)

    self.associationDelegate?.connectionManager(
      self, didCompleteAssociationWithCar: car)

    // Ensure that the list of peripherals to device ids is up to date.
    self.peripheralDeviceIds[peripheral.identifier] = car.id

    self.observations.securedChannel.values.forEach { observation in
      observation(self, securedCarChannel)
    }

    self.connectToAssociatedCars()
  }

  func associationManager(
    _ associationManager: AssociationManager,
    requiresDisplayOf pairingCode: String
  ) {
    associationDelegate?.connectionManager(self, requiresDisplayOf: pairingCode)
  }

  func associationManager(
    _ associationManager: AssociationManager,
    didEncounterError error: Error
  ) {
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.associationFailure)
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.associationDuration.end)
    associationDelegate?.connectionManager(self, didEncounterError: error)
  }

  func associationManager(
    _ associationManager: AssociationManager, didReceiveCarId carId: String
  ) {
    // A car can only be associated once with the companion app.
    if let existingCar = associatedCars.first(where: { $0.id == carId }) {
      log.error(
        "Found existing association for car id while completing association.",
        redacting: "id: \(carId)"
      )
      clearAssociation(for: existingCar)
    }
  }
}

// MARK: - ReconnectionHandlerFactory

extension ConnectionManager: ReconnectionHandlerFactory {
  func makeHandler(
    car: Car,
    connectionHandle: ConnectionHandle,
    secureSession: Data,
    messageStream: BLEMessageStream,
    secureBLEChannel: SecureBLEChannel,
    secureSessionManager: SecureSessionManager
  ) -> ReconnectionHandler {
    return ReconnectionHandlerImpl(
      car: car,
      connectionHandle: connectionHandle,
      secureSession: secureSession,
      messageStream: messageStream,
      secureBLEChannel: secureBLEChannel,
      secureSessionManager: secureSessionManager)
  }
}

// MARK: - CentralManagerDelegate

extension ConnectionManager: CentralManagerDelegate {
  public func centralManagerDidUpdateState(_ central: CentralManager) {
    state = central.state

    log(
      "CoreBluetooth state changed.",
      metadata: ["bluetooth.state": central.state.rawValue]
    )

    switch central.state {
    case .poweredOff:
      log(
        "CoreBluetooth BLE hardware is powered off",
        metadata: ["bluetooth.power": false]
      )

      // When Bluetooth is powered off, then all peripherals will be disconnected. However, the
      // system will not notify us of the disconnections nor can we call
      // `cancelPeripheralConnection` since the manager is off; so manually invoke it for all
      // connected peripherals.
      for peripheral in discoveredPeripherals {
        handleDisconnection(of: peripheral, error: nil)
      }
    case .poweredOn:
      log(
        "CoreBluetooth BLE hardware is powered on and ready",
        metadata: ["bluetooth.power": true]
      )

      // Ensure that scans restart if bluetooth is toggled off and on.
      if isAssociating {
        scanForCarsToAssociate(namePrefix: associationNamePrefix)
      } else {
        connectToAssociatedCars()
      }
    case .resetting:
      log("CoreBluetooth BLE hardware is resetting")
    case .unauthorized:
      log("CoreBluetooth BLE state is unauthorized")
    case .unknown:
      log("CoreBluetooth BLE state is unknown")
    case .unsupported:
      log("CoreBluetooth BLE hardware is unsupported")
    default:
      log.error("CoreBluetooth BLE unknown state: \(central.state.rawValue)")
    }

    observations.state.values.forEach { observation in
      observation(self, state)
    }

    if !state.isUnknown {
      // Perform any pending actions awaiting the state update.
      let actions = pendingPowerStateActions
      pendingPowerStateActions = []
      for action in actions {
        action(state)
      }
    }
  }

  public func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any]) {
    if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey]
      as? [CentralManager.Peripheral]
    {
      // Silence API misuse errors since we need to hold references to the restored peripherals as
      // the restoration mechanism attempts to reconnect them.
      discoveredPeripherals.formUnion(peripherals)
    }

    guard central.state == .poweredOn else {
      log("Restored central manager, but not powered on.")
      return
    }

    guard let services = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID],
      !services.isEmpty
    else {
      log("No services for restored central manager to resume scanning.")
      return
    }

    log(
      """
      Central Manager restored. Resuming scan for services: \
      [\(services.map { $0.uuidString }.joined(separator: ","))]
      """
    )

    central.scanForPeripherals(withServices: services, options: nil)
  }

  /// Called when a scan for peripherals that have the appropriate lock/unlock characteristics have
  /// been discovered.
  ///
  /// This method will notify any delegates of the discovery.
  public func centralManager(
    _ central: CentralManager,
    didDiscover peripheral: Peripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    log("centralManager did discover peripheral: \(peripheral.logName)")

    guard shouldConnect(to: peripheral) else { return }

    let advertisedName = resolveName(from: advertisementData)
    log(
      """
      Discovered device (\(peripheral.logName): \(peripheral.identifier.uuidString)). \
      Advertised name: <\(advertisedName ?? "no name")>.) State: \(peripheral.state.rawValue).
      """
    )
    // Nothing else to do if associating. Association relies on the user to explicitly call
    // associate(_:) for a connection.
    if isAssociating {
      handleDiscoveryForAssociation(of: peripheral, advertisedName: advertisedName)
      return
    }

    guard associationManager.isAssociated else {
      log("Discovered car during reconnection phase, but no cars associated. Ignoring.")
      return
    }

    discoveredPeripherals.insert(peripheral)
    attemptReconnection(with: peripheral, advertisementData: advertisementData)
  }

  private func handleDiscoveryForAssociation(of peripheral: Peripheral, advertisedName: String?) {
    // The name during association can come from the scan response, which iOS interprets as two
    // calls to this `didDiscover` callback. Thus, ignore any callbacks in which we cannot resolve
    // the name.
    guard let advertisedName = advertisedName else {
      log(
        """
        Discovered device (\(peripheral.logName): \(peripheral.identifier.uuidString)). \
        With no advertised name during association. Ignoring. State: \(peripheral.state.rawValue).
        """
      )
      return
    }
    guard associationAdvertisedNameFilter?(advertisedName) ?? true else {
      log("Discovered car but rejected for association by filter. Ignoring.")
      return
    }
    discoveredPeripherals.insert(peripheral)
    let fullName =
      requiresNamePrefix(advertisedName) ? associationNamePrefix + advertisedName : advertisedName

    associationDelegate?.connectionManager(self, didDiscover: peripheral, advertisedName: fullName)
  }

  private func resolveName(from advertisementData: [String: Any]) -> String? {
    // The advertised name can come from two sources. In newer versions, the name is stored in the
    // scan response and retrievable by the `associationDataUUID`. Otherwise, it's the standard
    // advertised name.
    guard
      let dataContents = advertisementData[CBAdvertisementDataServiceDataKey] as? NSDictionary,
      let rawData = dataContents[uuidConfig.associationDataUUID] as? Data
    else {
      log("Retrieving default advertised name from advertisement data.")

      // iOS will cache the name of the discovered peripheral if it is paired via Bluetooth. This
      // means `peripheral.name` might not be up to date. As a result, manually read the advertised
      // name to use as a backup name.
      return advertisementData[CBAdvertisementDataLocalNameKey] as? String
    }

    if rawData.count == advertisementLengthForUTF8Conversion {
      log("Retrieving advertised name with association UUID using UTF-8.")
      return String(decoding: rawData, as: UTF8.self)
    }

    log("Advertisement data of length \(rawData.count). Converting to hex value.")
    return rawData.hex
  }

  /// Returns `true` if the `advertisedName` is a new version name and a prefix needs to be
  /// prepended.
  private func requiresNamePrefix(_ advertisedName: String) -> Bool {
    return advertisedName.count != advertisementLengthForUTF8Conversion
  }

  /// Returns `true` if a connection should be attempted with the given `peripheral`.
  ///
  /// A peripheral should be connected with if a previous connection attempt has not already been
  /// initiated with it.
  private func shouldConnect(to peripheral: Peripheral) -> Bool {
    if !discoveredPeripherals.contains(peripheral) {
      return true
    }

    if peripheral.state == .disconnected {
      log("Device already discovered before, but disconnected. Proceeding with connection.")

      return true
    }

    // Check if this class believes the peripheral to already be connected securely. If it is, then
    // discovering it again means that they are actually disconnected now.
    for channel in securedChannels {
      if let connectedPeripheral = self.peripheral(from: channel),
        peripheral.identifier == connectedPeripheral.identifier
      {
        log(
          """
          Duplicate peripheral discovered that has secure session. Disconnecting. \
          Peripheral state: \(peripheral.state.rawValue)
          """
        )

        // This disconnection should clean up the `securedChannels`.
        disconnect(peripheral)
        return false
      }
    }

    log(
      """
      Duplicate peripheral discovered without secure channel. Proceeding with connection. \
      Peripheral state: \(peripheral.state.rawValue).
      """
    )

    // A device might be believed to be "connected" because it has an existing Bluetooth connection
    // but not BLE connection. As a result, it's ok to proceed with connection.
    return true
  }

  private func attemptReconnection(with peripheral: Peripheral, advertisementData: [String: Any]) {
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.reconnectionDuration.begin)
    do {
      let reconnectionHelper = try reconnectionHelperFactory.makeHelper(
        peripheral: peripheral,
        advertisementData: advertisementData,
        associatedCars: associatedCars,
        uuidConfig: uuidConfig,
        authenticator: CarAuthenticatorImpl.self
      )

      // The peripheral to device id mapping is needed for security version 2.
      if let carId = reconnectionHelper.carId {
        peripheralDeviceIds[peripheral.identifier] = carId
      }

      communicationManager.addReconnectionHelper(reconnectionHelper)

      log("Attempting to connect to device (\(peripheral.logName))")

      connect(with: peripheral)
      return
    } catch CommunicationManagerError.notAssociated {
      log.error("No associated car found corresponding to device (\(peripheral.logName))")
    } catch {
      log.error(
        """
        Error: <\(error.localizedDescription)> encountered making reconnection helper \
        for device (\(peripheral.logName))
        """
      )
    }

    // An error could mean that there is still another user on the device associated with this
    // phone. So remove it from the list so it can be discovered again if it re-advertises.
    disconnect(peripheral)
  }

  /// Called when a connection to a peripheral is successful.
  ///
  /// Attempt to discover the appropriate lock or unlock characteristics on the connected
  /// peripheral depending on if `scanToAssociate` or `scanToUnlock` was called.
  public func centralManager(_ central: CentralManager, didConnect peripheral: Peripheral) {
    onPeripheralConnected(peripheral)

    // If not associated, notify the delegate. Otherwise, this manager will handle the connection
    // flow, so no need to notify.
    if isAssociating {
      log(
        """
        Car (\(peripheral.logName)) connected. \
        Proceeding with association flow and notifying delegate.
        """
      )

      associationDelegate?.connectionManager(self, didConnect: peripheral)
      associate(peripheral: peripheral)
      return
    }

    log(
      """
      Car (name: \(peripheral.logName)) connected. \
      Attempting to establish secure communication with car.
      """
    )

    setupSecureChannel(with: peripheral)
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.reconnectionDuration.end)
    signpostMetrics.postIfAvailable(ConnectionManagerSignposts.reconnectionCompletion)
  }

  public func centralManager(
    _ central: CentralManager,
    didDisconnectPeripheral peripheral: Peripheral,
    error: Error?
  ) {
    handleDisconnection(of: peripheral, error: error)
  }

  public func centralManager(
    _ central: CentralManager,
    didFailToConnect peripheral: CentralManager.Peripheral,
    error: Error?
  ) {
    handleConnectionFailure(of: peripheral, error: error)
  }

  fileprivate func handleConnectionFailure(of peripheral: Peripheral, error: Error?) {
    let error = error as NSError? ?? NSError(domain: "ConnectionManagerError", code: 1)

    let resolvedError = resolveError(error)
    onPeripheralConnectionFailed(peripheral, error: error)
    if isAssociating {
      associationDelegate?.connectionManager(self, didEncounterError: resolvedError)
      isAssociating = false
      clearCurrentAssociation()
    }
  }

  fileprivate func handleDisconnection(of peripheral: Peripheral, error: Error?) {
    // Usually this method is called by a system event, but it might also be triggered manually by
    // this class. Ensure that it is really disconnected.
    centralManager.cancelPeripheralConnection(peripheral)

    discoveredPeripherals.remove(peripheral)
    onPeripheralDisconnected(peripheral)

    // A disconnect during association is considered an error since the user will be forced to
    // through the entire process again.
    if isAssociating {
      associationDelegate?.connectionManager(self, didEncounterError: AssociationError.disconnected)
    }

    // After a disconnection, resume scans for any associated cars to ensure that if the car comes
    // back in range again, it will be connected to.
    defer {
      scanForAssociatedCarsAfterDelay()
    }

    guard let id = peripheralDeviceIds.removeValue(forKey: peripheral.identifier) else {
      log(
        "Device disconnected, but no device id, meaning device ids have not been exchanged yet.")
      return
    }

    // Remove any secured channels that contain the given car that just disconnected as they should
    // now be invalid.
    securedChannels = securedChannels.filter { $0.car.id != id }

    // Only notify observers if the device is associated.
    guard associatedCarsManager.identifiers.contains(id) else {
      log("Disconnected from un-associated car (id: \(id)).")
      return
    }

    log("Disconnected from associated car (id: \(id)). Notifying observers.")

    observations.disconnected.values.forEach { observation in
      observation(self, Car(id: id, name: peripheral.name))
    }
  }

  private func scanForAssociatedCarsAfterDelay() {
    let connectHandler = DispatchWorkItem { [weak self] in
      // If the user was associating, then they need to explicitly stop association scans before
      // we start another scan. This is to prevent a race condition where the users requests an
      // association scan in between this disconnect and a rescan.
      if self?.isAssociating == false {
        self?.connectToAssociatedCars()
      }
    }

    // Delay the scan for a couple seconds to allow the state of connection to flush from the
    // system.
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(2), execute: connectHandler)
  }
}

/// Wraps the central manager and forwards its delegate callbacks to the connection manager.
///
/// We need this class because Objective-C protocol requirements can't be satisfied
/// by a generic equivalent. Namely we need this to handle `CBCentralManagerDelegate`.
private class CoreBluetoothCentralManagerWrapper: NSObject {
  private static let log = Logger(for: CoreBluetoothCentralManagerWrapper.self)

  /// The key that is passed to the central manager to enable state restoration.
  private static var centralManagerRestoreKey =
    "com.google.ios.aae.trustagentclient.CBCentralManagerRestoreKey"

  weak fileprivate var connectionManager: CoreBluetoothConnectionManager?
  fileprivate var centralManager: CBCentralManager!

  override init() {
    // Calling `super` here so that subsequent code can use `self`.
    super.init()

    // Use a serialized queue to ensure that all requests are processed in-order.
    centralManager = CBCentralManager(
      delegate: self,
      queue: nil,
      options: [
        CBCentralManagerOptionShowPowerAlertKey: true,
        CBCentralManagerOptionRestoreIdentifierKey: Self.centralManagerRestoreKey,
      ]
    )
  }
}

// MARK: - CBCentralManagerDelegate

// Ugh! We need this class to forward to the connection manager since Objective-C doesn't
// allow conditional conformance to an objc protocol. So we can't provide conditional
// conformance for ConnectionManager to CBCentralManagerDelegate.
extension CoreBluetoothCentralManagerWrapper: CBCentralManagerDelegate {
  public func centralManagerDidUpdateState(_ central: CBCentralManager) {
    Task {
      await connectionManager?.centralManagerDidUpdateState(central)
    }
  }

  public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
    Task {
      await connectionManager?.centralManager(central, willRestoreState: dict)
    }
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    Task {
      await connectionManager?.centralManager(
        central,
        didDiscover: peripheral,
        advertisementData: advertisementData,
        rssi: RSSI)
    }
  }

  /// Called when a connection to a peripheral is successful.
  ///
  /// Attempt to discover the appropriate lock or unlock characteristics on the connected
  /// peripheral depending on if `scanToAssociate` or `scanToUnlock` was called.
  public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    Task {
      await connectionManager?.centralManager(central, didConnect: peripheral)
    }
  }

  public func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    Task {
      await connectionManager?.centralManager(
        central, didDisconnectPeripheral: peripheral, error: error)
    }
  }

  public func centralManager(
    _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
  ) {
    Task {
      await connectionManager?.centralManager(central, didFailToConnect: peripheral, error: error)
    }
  }
}

// MARK: - Peripheral and Central Manager Protocols

public protocol AnyPeripheral {
  var identifier: UUID { get }
  var name: String? { get }
}

/// Homogeneous protocol that any peripheral should implement so we can abstract
/// away from Core Bluetooth.
public protocol SomePeripheral: AnyPeripheral, Hashable {
  var state: CBPeripheralState { get }
}

/// Common protocol that all central managers should implement so we can abstract
/// away from Core Bluetooth.
public protocol SomeCentralManager {
  associatedtype Peripheral: SomePeripheral

  var state: CBManagerState { get }
  var isScanning: Bool { get }

  func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [Peripheral]
  func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?)
  func stopScan()
  func connect(_ peripheral: Peripheral, options: [String: Any]?)
  func cancelPeripheralConnection(_ peripheral: Peripheral)
}

// MARK: - AnyPeripheral extensions

/// Default implementations.
extension AnyPeripheral {
  /// Returns a log-friendly name.
  public var logName: String { name ?? "no name" }
}

// MARK: - CoreBluetooth extensions

/// Formally declare CBPeripheral to conform to `SomePeripheral`.
extension CBPeripheral: SomePeripheral {
  // Empty - already conforms to the protocol requirements
}

/// Formally declare CBCentralManager to conform to `SomeCentralManager`.
extension CBCentralManager: SomeCentralManager {
  public typealias Peripheral = CBPeripheral
}

/// Delegate for all central managers that mirrors CBCentralManagerDelegate.
public protocol CentralManagerDelegate {
  associatedtype CentralManager: SomeCentralManager

  func centralManagerDidUpdateState(_ central: CentralManager)

  func centralManager(_ central: CentralManager, willRestoreState dict: [String: Any])

  /// Called when a scan for peripherals that have the appropriate lock/unlock characteristics have
  /// been discovered.
  ///
  /// This method will notify any delegates of the discovery.
  func centralManager(
    _ central: CentralManager,
    didDiscover peripheral: CentralManager.Peripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  )

  /// Called when a connection to a peripheral is successful.
  ///
  /// Attempt to discover the appropriate lock or unlock characteristics on the connected peripheral
  /// depending on if `scanToAssociate` or `scanToUnlock` was called.
  func centralManager(
    _ central: CentralManager,
    didConnect peripheral: CentralManager.Peripheral
  )

  func centralManager(
    _ central: CentralManager,
    didDisconnectPeripheral peripheral: CentralManager.Peripheral,
    error: Error?
  )

  func centralManager(
    _ central: CentralManager,
    didFailToConnect: CentralManager.Peripheral,
    error: Error?
  )
}

/// Provide `RadioState` conformance.
extension CBManagerState: RadioState {
  public var description: String {
    switch self {
    case .poweredOn:
      return "poweredOn"
    case .poweredOff:
      return "poweredOff"
    case .unknown:
      return "unknown"
    default:
      return "other"
    }
  }

  public var isPoweredOn: Bool {
    self == .poweredOn
  }

  public var isPoweredOff: Bool {
    self == .poweredOff
  }

  public var isUnknown: Bool {
    self == .unknown
  }

  public var isOther: Bool {
    !isPoweredOn && !isPoweredOff && !isUnknown
  }
}
