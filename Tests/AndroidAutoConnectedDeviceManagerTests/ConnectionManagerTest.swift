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

private import AndroidAutoCoreBluetoothProtocolsMocks
internal import AndroidAutoSecureChannel
private import CoreBluetooth
internal import Foundation
internal import XCTest
private import os
import AndroidAutoCompanionProtos

@testable private import AndroidAutoConnectedDeviceManager
@testable private import AndroidAutoConnectedDeviceManagerMocks

private typealias OutOfBandAssociationData = Com_Google_Companionprotos_OutOfBandAssociationData
private typealias OutOfBandAssociationToken = Com_Google_Companionprotos_OutOfBandAssociationToken

/// Unit tests for `CommunicationManager`. Specifically testing the version 2 flow.
class ConnectionManagerTest: XCTestCase {
  private var connectionManager: ConnectionManagerObservable!
  private var centralManagerMock: CentralManagerMock!
  private var associatedCarsManager: AssociatedCarsManagerMock!
  private var associationDelegateMock: ConnectionManagerAssociationDelegateMock!
  private var uuidConfig: UUIDConfig!
  private var versionResolverFake: BLEVersionResolverFake!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    await setUpOnMain()
  }

  @MainActor private func setUpOnMain() {
    uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    versionResolverFake = BLEVersionResolverFake()

    centralManagerMock = CentralManagerMock()

    associatedCarsManager = AssociatedCarsManagerMock()
    connectionManager = ConnectionManagerObservable(
      centralManager: centralManagerMock,
      associatedCarsManager: associatedCarsManager,
      reconnectionHelperFactory: ReconnectionHelperFactoryImpl.self
    )

    associationDelegateMock = ConnectionManagerAssociationDelegateMock()
    connectionManager.associationDelegate = associationDelegateMock
  }

  // MARK: ConnectionManager -> CentralManager

  @MainActor func testConnectionManagerStopScan_CentralManagerStopsScan() {
    connectionManager.stopScanning()
    XCTAssertTrue(centralManagerMock.stopScanCalled)
  }

  // MARK: - Lifecycle calls

  @MainActor func testCentralManager_callsConnectOnAssociate() {
    let peripheralMock = PeripheralMock(name: "Test")

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    XCTAssertEqual(connectionManager.connectCalledCount, 1)
    XCTAssert(connectionManager.peripheralToConnect === peripheralMock)
  }

  @MainActor func testCentralManager_callsOnPeripheralConnected_whenConnectionEstablished() {
    let peripheralMock = PeripheralMock(name: "Test")

    connectionManager.centralManager(centralManagerMock, didConnect: peripheralMock)

    XCTAssertTrue(connectionManager.onPeripheralConnectedCalled)
    XCTAssert(connectionManager.connectedPeripheral === peripheralMock)
  }

  @MainActor func testCentralManager_callsOnPeripheralDisconnected_whenPeripheralDisconnects() {
    let peripheralMock = PeripheralMock(name: "Test")

    connectionManager.centralManager(
      centralManagerMock,
      didDisconnectPeripheral: peripheralMock,
      error: makeMockError())

    XCTAssertTrue(connectionManager.onPeripheralDisconnectedCalled)
    XCTAssert(connectionManager.disconnectedPeripheral === peripheralMock)
  }

  @MainActor func testCentralManager_cancelsPeripheralConnection_whenPeripheralDisconnects() {
    let peripheralMock = PeripheralMock(name: "Test")

    connectionManager.centralManager(
      centralManagerMock,
      didDisconnectPeripheral: peripheralMock,
      error: makeMockError())

    XCTAssertTrue(centralManagerMock.cancelPeripheralConnectionCalled)
  }

  @MainActor func testCentralManager_callsOnPeripheralConnectionFailed_whenConnectionFails() {
    let peripheralMock = PeripheralMock(name: "Test")
    let mockError = makeMockError() as NSError

    connectionManager.centralManager(
      centralManagerMock,
      didFailToConnect: peripheralMock,
      error: mockError)

    XCTAssertTrue(connectionManager.onPeripheralConnectionFailedCalled)
    XCTAssertEqual(connectionManager.failedConnectionPeripheral, peripheralMock)
    XCTAssertEqual(connectionManager.failedConnectionError, mockError)
  }

  @MainActor func testCentralManager_peripheralConnectionFailsOnAssociation_notifiesDelegate() {
    let peripheralMock = PeripheralMock(name: "Test")
    let mockError = makeMockError() as NSError

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    connectionManager.centralManager(
      centralManagerMock,
      didFailToConnect: peripheralMock,
      error: mockError)

    XCTAssertTrue(associationDelegateMock.didEncounterErrorCalled)
    XCTAssertEqual(associationDelegateMock.encounteredError as? AssociationError, .unknown)
  }

  @MainActor func testCentralManager_peripheralDisconnectsOnAssociation_notifiesDelegate() {
    let peripheralMock = PeripheralMock(name: "Test")

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    connectionManager.centralManager(
      centralManagerMock,
      didDisconnectPeripheral: peripheralMock,
      error: nil)

    XCTAssertTrue(associationDelegateMock.didEncounterErrorCalled)
    XCTAssertEqual(associationDelegateMock.encounteredError as? AssociationError, .disconnected)
  }

  @MainActor func testCentralManager_peripheralDisconnectsNotAssociating_doesNotNotifyDelegate() {
    let peripheralMock = PeripheralMock(name: "Test")

    connectionManager.centralManager(
      centralManagerMock,
      didDisconnectPeripheral: peripheralMock,
      error: nil)

    XCTAssertFalse(associationDelegateMock.didEncounterErrorCalled)
  }

  @MainActor func testCentralManager_associates_whenConnectionEstablished() {
    let peripheralMock = PeripheralMock(name: "Test")

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))
    connectionManager.centralManager(centralManagerMock, didConnect: peripheralMock)

    XCTAssertTrue(connectionManager.associateCalled)
  }

  @MainActor func testCentralManager_setUpSecureChannel_whenConnectionEstablished() {
    let peripheralMock = PeripheralMock(name: "Test")

    connectionManager.centralManager(centralManagerMock, didConnect: peripheralMock)

    XCTAssertTrue(connectionManager.setupSecureChannelCalled)
  }

  @MainActor func testCentralManager_registerServiceObservers_onAssociationComplete() {
    let peripheralMock = PeripheralMock(name: "Test")
    let car = Car(id: "id", name: "test")
    let secureChannel = SecuredCarChannelMock(id: car.id, name: car.name)

    connectionManager.associationManager(
      makeAssociationManagerMock(),
      didCompleteAssociationWithCar: car,
      securedCarChannel: secureChannel,
      peripheral: peripheralMock)

    XCTAssertTrue(connectionManager.registerServiceObserverCalled)
    XCTAssert(connectionManager.observedChannel === secureChannel)
  }

  @MainActor func testCentralManager_registerServiceObservers_onSecureChannelEstablished() {
    let secureChannel = SecuredCarChannelMock(id: "id", name: "Test")

    connectionManager.communicationManager(
      makeCommunicationManager(),
      didEstablishSecureChannel: secureChannel)

    XCTAssertTrue(connectionManager.registerServiceObserverCalled)
    XCTAssert(connectionManager.observedChannel === secureChannel)
  }

  // MARK: CentralManagerDelegate calls

  @MainActor func testCentralManagerDidUpdateState() {
    centralManagerMock.state = .poweredOff
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isPoweredOff)

    centralManagerMock.state = .poweredOn
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isPoweredOn)

    centralManagerMock.state = .resetting
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isOther)

    centralManagerMock.state = .unsupported
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isOther)

    centralManagerMock.state = .unauthorized
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isOther)

    centralManagerMock.state = .unknown
    connectionManager.centralManagerDidUpdateState(centralManagerMock)
    XCTAssertTrue(connectionManager.state.isUnknown)
  }

  @MainActor func testRequestRadioStateActionPended_PoweredOn() {
    centralManagerMock.state = .unknown
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    var actionPerformed = false
    var state: any RadioState = CBManagerState.unknown
    connectionManager.requestRadioStateAction {
      state = $0
      actionPerformed = true
    }

    XCTAssertFalse(actionPerformed)

    centralManagerMock.state = .poweredOn
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    XCTAssertTrue(actionPerformed)
    XCTAssertTrue(state.isPoweredOn)
  }

  @MainActor func testRequestRadioStateActionPended_PoweredOff() {
    centralManagerMock.state = .unknown
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    var actionPerformed = false
    var state: any RadioState = CBManagerState.unknown
    connectionManager.requestRadioStateAction {
      state = $0
      actionPerformed = true
    }

    XCTAssertFalse(actionPerformed)

    centralManagerMock.state = .poweredOff
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    XCTAssertTrue(actionPerformed)
    XCTAssertTrue(state.isPoweredOff)
  }

  @MainActor func testRequestRadioStateActionImmediate_PoweredOn() {
    centralManagerMock.state = .poweredOn
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    var actionPerformed = false
    var state: any RadioState = CBManagerState.unknown
    connectionManager.requestRadioStateAction {
      state = $0
      actionPerformed = true
    }

    XCTAssertTrue(actionPerformed)
    XCTAssertTrue(state.isPoweredOn)
  }

  @MainActor func testRequestRadioStateActionImmediate_PoweredOff() {
    centralManagerMock.state = .poweredOff
    connectionManager.centralManagerDidUpdateState(centralManagerMock)

    var actionPerformed = false
    var state: any RadioState = CBManagerState.unknown
    connectionManager.requestRadioStateAction {
      state = $0
      actionPerformed = true
    }

    XCTAssertTrue(actionPerformed)
    XCTAssertTrue(state.isPoweredOff)
  }

  @MainActor func testCentralManagerPoweredOnAndWillRestoreState_ScansForPeripherals() {
    centralManagerMock.state = .poweredOn
    let restorationState = RestorationState<CentralManagerMock>(
      state: [CBCentralManagerRestoredStateScanServicesKey: [CBUUID()]]
    )
    connectionManager.centralManager(centralManagerMock, willRestoreState: restorationState)
    XCTAssertTrue(centralManagerMock.scanForPeripheralsCalled)
  }

  // MARK: -  Association delegate tests

  @MainActor func testCentralManager_scansForAssociationUUID_fromUUIDConfig() {
    connectionManager.scanForCarsToAssociate(namePrefix: "Prefix")

    XCTAssertTrue(centralManagerMock.scanForPeripheralsCalled)
    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 1)
    XCTAssert(centralManagerMock.servicesToScanFor!.contains(uuidConfig.associationUUID))
  }

  @MainActor func testCentralManager_scansForAssociationUUID_fromAssociationConfig() {
    let associationUUID = CBUUID(string: "4ea3eae4-b861-4a09-ad30-ce80e6a7b1ae")

    connectionManager.scanForCarsToAssociate(namePrefix: "Prefix") { config in
      config.associationUUID = associationUUID
    }

    XCTAssertTrue(centralManagerMock.scanForPeripheralsCalled)
    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 1)
    XCTAssert(centralManagerMock.servicesToScanFor!.contains(associationUUID))
  }

  @MainActor func testCentralManager_scansForAssociationUUID_fromUUIDConfigAndAssociationConfig() {
    let associationUUID = CBUUID(string: "4ea3eae4-b861-4a09-ad30-ce80e6a7b1ae")

    connectionManager.scanForCarsToAssociate(namePrefix: "Prefix") { config in
      config.associationUUID = associationUUID
    }

    XCTAssertTrue(centralManagerMock.scanForPeripheralsCalled)
    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 1)
    XCTAssert(centralManagerMock.servicesToScanFor!.contains(associationUUID))

    // Second call should go back to default values.
    connectionManager.scanForCarsToAssociate(namePrefix: "Prefix")

    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 1)
    XCTAssert(centralManagerMock.servicesToScanFor!.contains(uuidConfig.associationUUID))
  }

  @MainActor func testCentralManagerDidDiscoverPeripheral_doesNotNotifyDelegateIfNoName() {
    let peripheralMock = PeripheralMock(name: "Test")

    let advertisement = Advertisement()
    connectionManager.centralManager(
      centralManagerMock, didDiscover: peripheralMock, advertisement: advertisement, rssi: 1.0)

    XCTAssertFalse(associationDelegateMock.discoveredCars.contains(peripheralMock))
  }

  @MainActor func testCentralManagerDidDiscoverPeripheral_doesNotNotifyDelegateIfNotAssociating() {
    let peripheralMock = PeripheralMock(name: "Test")

    let advertisement: Advertisement = [CBAdvertisementDataLocalNameKey: "advertisedName"]
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: advertisement,
      rssi: 1.0)

    XCTAssertFalse(associationDelegateMock.discoveredCars.contains(peripheralMock))
  }

  @MainActor func testCentralManagerDidDiscoverPeripheral_notifiesAssociationDelegateIfAssociating()
  {
    let peripheralMock = PeripheralMock(name: "Test")
    let advertisedName = "advertisedName"

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataLocalNameKey: advertisedName],
      rssi: 1.0)

    XCTAssertTrue(connectionManager.discoveredPeripherals.contains(peripheralMock))

    XCTAssertTrue(associationDelegateMock.discoveredCars.contains(peripheralMock))
    XCTAssertEqual(associationDelegateMock.advertisedName, advertisedName)
  }

  // MARK: - Discovered peripheral name tests.

  @MainActor func testCentralManagerDidDiscoverPeripheral_notifiesWithUTF8NameAndNoPrefix() {
    let peripheralMock = PeripheralMock(name: "Test")
    let advertisedName = "advertisedName"

    /// UTF-8 encoding requires the name be 8 bytes long
    let utf8Name = "12345678"
    let namePrefix = "namePrefix "

    connectionManager.scanForCarsToAssociate(namePrefix: namePrefix)

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    let advertisement: Advertisement = [
      CBAdvertisementDataLocalNameKey: advertisedName,
      CBAdvertisementDataServiceDataKey: [uuidConfig.associationDataUUID: Data(utf8Name.utf8)],
    ]

    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: advertisement,
      rssi: 1.0)

    XCTAssertTrue(connectionManager.discoveredPeripherals.contains(peripheralMock))
    XCTAssertTrue(associationDelegateMock.discoveredCars.contains(peripheralMock))

    XCTAssertEqual(associationDelegateMock.advertisedName, utf8Name)
  }

  @MainActor func testCentralManagerDidDiscoverPeripheral_notifiesWithHexName() {
    let peripheralMock = PeripheralMock(name: "Test")
    let advertisedName = "advertisedName"
    let namePrefix = "namePrefix "

    /// The hex name just needs to be a length that is not 8 bytes.
    let hexName = "2AF8"
    let hexNameData = Data(hex: hexName)!

    connectionManager.scanForCarsToAssociate(namePrefix: namePrefix)

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    let advertisement: Advertisement = [
      CBAdvertisementDataLocalNameKey: advertisedName,
      CBAdvertisementDataServiceDataKey: [uuidConfig.associationDataUUID: hexNameData],
    ]

    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: advertisement,
      rssi: 1.0)

    XCTAssertTrue(connectionManager.discoveredPeripherals.contains(peripheralMock))
    XCTAssertTrue(associationDelegateMock.discoveredCars.contains(peripheralMock))

    let expectedName = "\(namePrefix)\(hexName)"
    XCTAssertEqual(associationDelegateMock.advertisedName, expectedName)
  }

  @MainActor
  func testCentralManagerDidDiscoverPeripheralWithNameFilter_notifiesWithHexNameAndNamePrefix()
    throws
  {
    let peripheralMock = PeripheralMock(name: "Test")
    let advertisedName = "advertisedName"
    let namePrefix = "namePrefix "

    /// The hex name just needs to be a length that is not 8 bytes.
    let hexName = "2AF8"
    let hexNameData = Data(hex: hexName)!

    // Construct out of band data source.
    var outOfBandData = OutOfBandAssociationData()
    outOfBandData.token = OutOfBandAssociationToken()
    outOfBandData.deviceIdentifier = Data(hex: hexName)!
    let querySafeBase64 = try outOfBandData.serializedData().base64EncodedString()
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
    let url = URL(string: "http://companion/associate?oobData=\(querySafeBase64)")
    let dataSource = try OutOfBandAssociationDataSource(url!)

    connectionManager.scanForCarsToAssociate(namePrefix: namePrefix, outOfBandSource: dataSource)
    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    let advertisement: Advertisement = [
      CBAdvertisementDataLocalNameKey: advertisedName,
      CBAdvertisementDataServiceDataKey: [uuidConfig.associationDataUUID: hexNameData],
    ]
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: advertisement,
      rssi: 1.0)

    XCTAssertTrue(connectionManager.discoveredPeripherals.contains(peripheralMock))
    XCTAssertTrue(associationDelegateMock.discoveredCars.contains(peripheralMock))

    let expectedName = "\(namePrefix)\(hexName)"
    XCTAssertEqual(associationDelegateMock.advertisedName, expectedName)
  }

  @MainActor
  func testCentralManagerDidDiscoverPeripheralWithNameFilter_doNotNotifyDelegateWithUTF8Name()
    throws
  {
    let peripheralMock = PeripheralMock(name: "Test")
    let advertisedName = "advertisedName"

    /// UTF-8 encoding requires the name be 8 bytes long
    let utf8Name = "12345678"
    let namePrefix = "namePrefix "

    /// The hex name just needs to be a length that is not 8 bytes.
    let hexName = "2AF8"
    let hexNameData = Data(hex: hexName)!

    // Create QR code out of band data source.
    var outOfBandData = OutOfBandAssociationData()
    outOfBandData.token = OutOfBandAssociationToken()
    outOfBandData.deviceIdentifier = hexNameData
    let querySafeBase64 = try outOfBandData.serializedData().base64EncodedString()
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
    let url = URL(string: "http://companion/associate?oobData=\(querySafeBase64)")
    let dataSource = try OutOfBandAssociationDataSource(url!)

    connectionManager.scanForCarsToAssociate(namePrefix: namePrefix, outOfBandSource: dataSource)
    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    let advertisement: Advertisement = [
      CBAdvertisementDataLocalNameKey: advertisedName,
      CBAdvertisementDataServiceDataKey: [uuidConfig.associationDataUUID: Data(utf8Name.utf8)],
    ]

    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: advertisement,
      rssi: 1.0)

    XCTAssertFalse(associationDelegateMock.discoveredCars.contains(peripheralMock))
  }

  // MARK: - Disconnection tests.

  @MainActor func testCentralManagerDidDisconnectPeripheral() {
    let peripheralMock = PeripheralMock(name: "Test")
    connectionManager.discoveredPeripherals.insert(peripheralMock)
    connectionManager.centralManager(
      centralManagerMock, didDisconnectPeripheral: peripheralMock, error: nil)
    XCTAssertFalse(associationDelegateMock.discoveredCars.contains(peripheralMock))
  }

  @MainActor func testCentralManager_didConnect_callsAssociationDelegate() {
    let peripheralMock = PeripheralMock(name: "Test")

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))
    connectionManager.centralManager(centralManagerMock, didConnect: peripheralMock)

    XCTAssert(associationDelegateMock.didConnectCalledForPeripherals.contains(peripheralMock))
  }

  @MainActor func testDisconnectPeripheral_associating_alreadyDisconnected_notifiesDelegate() {
    let peripheralMock = PeripheralMock(name: "Test")

    XCTAssertNoThrow(try connectionManager.associate(peripheralMock))

    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataLocalNameKey: "advertisedName"],
      rssi: 1.0)

    peripheralMock.state = .disconnected

    connectionManager.disconnect(peripheralMock)

    XCTAssertTrue(associationDelegateMock.didEncounterErrorCalled)
  }

  @MainActor func testAssociatingExistingCarId_removesExistingCarAssociation() {
    // Add a couple associated cars.
    associatedCarsManager.addAssociatedCar(identifier: "Good", name: "Good")
    associatedCarsManager.addAssociatedCar(identifier: "Test", name: "Test")

    // A duplicate car id was received during association.
    connectionManager.associationManager(makeAssociationManagerMock(), didReceiveCarId: "Test")

    // The existing associated car matching the duplicate id should be cleared.
    XCTAssertNil(associatedCarsManager.data["Test"] as Any?)
    XCTAssertNotNil(associatedCarsManager.data["Good"] as Any?)
  }

  @MainActor func testAssociatingUniqueCarId_doesNotRemoveExistingCarAssociation() {
    // Add a couple associated cars.
    associatedCarsManager.addAssociatedCar(identifier: "Good", name: "Good")

    // A duplicate car id was received during association.
    connectionManager.associationManager(makeAssociationManagerMock(), didReceiveCarId: "Test")

    // The existing associated cars are left unchanged.
    XCTAssertNotNil(associatedCarsManager.data["Good"] as Any?)
  }

  @MainActor func testAssociating_afterDisconnecting_scanIsNotOverridden() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)
    setPeripheralAssociated(peripheralMock)

    // Simulate a device being discovered and then connected to.
    connectionManager.centralManager(
      centralManagerMock, didDiscover: peripheralMock, advertisement: ["": ""], rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    let scanForPeripheralsExpectation =
      XCTestExpectation(description: "Scan for peripherals with association UUID expectation")

    centralManagerMock.scanForPeripheralsExpectation = scanForPeripheralsExpectation

    peripheralMock.state = .disconnected

    connectionManager.disconnect(peripheralMock)
    connectionManager.scanForCarsToAssociate(namePrefix: "name")

    wait(for: [scanForPeripheralsExpectation], timeout: 2.0)

    XCTAssertEqual(centralManagerMock.servicesToScanFor!.count, 1)
    XCTAssert(centralManagerMock.servicesToScanFor!.contains(uuidConfig.associationUUID))
  }

  // MARK: - Reconnection flow

  @MainActor func testCentralManager_withNoAssociatedCars_doesNotScan() {
    connectionManager.connectToAssociatedCars()
    XCTAssertFalse(centralManagerMock.scanForPeripheralsCalled)
  }

  @MainActor func testCentralManager_scansForAllReconnectionUUIDs() {
    // Set up a random peripheral as being associated so that a scan will start.
    setPeripheralAssociated(PeripheralMock(name: "test"))

    connectionManager.connectToAssociatedCars()

    XCTAssertTrue(centralManagerMock.scanForPeripheralsCalled)

    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 2)

    let servicesToScanFor = centralManagerMock.servicesToScanFor!
    XCTAssert(servicesToScanFor.contains(uuidConfig.reconnectionUUID(for: .v1)))
    XCTAssert(servicesToScanFor.contains(uuidConfig.reconnectionUUID(for: .v2)))
  }

  @MainActor func testCentralManager_errorDuringReconnection_notifiesObserver() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)

    // Simulate a device being discovered and then connected to.
    connectionManager.centralManager(
      centralManagerMock, didDiscover: peripheralMock, advertisement: ["": ""], rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    connectionManager.communicationManager(
      makeCommunicationManager(),
      didEncounterError: .unknown,
      whenReconnecting: peripheralMock)

    XCTAssertTrue(centralManagerMock.cancelPeripheralConnectionCalled)
    XCTAssertTrue(centralManagerMock.canceledPeripherals.contains(where: { $0 === peripheralMock }))
  }

  @MainActor func testCentralManager_reconnectsForDuplicateDevice_ifDisconnected() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)

    setPeripheralAssociated(peripheralMock)

    // Advertisement data here corresponds to v1.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    peripheralMock.state = .disconnected

    // Same device is discovered again.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)

    XCTAssertFalse(centralManagerMock.cancelPeripheralConnectionCalled)
    XCTAssertFalse(
      centralManagerMock.canceledPeripherals.contains(where: { $0 === peripheralMock }))
    XCTAssertEqual(connectionManager.connectCalledCount, 2)
  }

  @MainActor func testCentralManager_reconnectsDuplicateDevice_ifNoSecureChannel() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)

    setPeripheralAssociated(peripheralMock)

    // Advertisement data here corresponds to v1.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    // Same device is discovered again.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)

    // Peripheral should not have been disconnected, but connected.
    XCTAssertFalse(centralManagerMock.cancelPeripheralConnectionCalled)
    XCTAssertFalse(centralManagerMock.canceledPeripherals.contains(peripheralMock))
    XCTAssertEqual(connectionManager.connectCalledCount, 2)
  }

  @MainActor func testCentralManager_doesReconnectDuplicateDevice_ifSecureChannelExists() {
    // Existing secure channel
    let secureChannel = SecuredCarChannelMock(id: "id", name: "Test")
    connectionManager.communicationManager(
      makeCommunicationManager(),
      didEstablishSecureChannel: secureChannel)

    let peripheralMock = secureChannel.peripheral as! PeripheralMock
    centralManagerMock.connectedPeripherals.insert(peripheralMock)

    setPeripheralAssociated(peripheralMock)

    // Advertisement data here corresponds to v1.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    // Same device is discovered again.
    connectionManager.centralManager(
      centralManagerMock,
      didDiscover: peripheralMock,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [DeviceIdManager.deviceId]],
      rssi: 1.0)

    // Peripheral should have been disconnected, but no connection called.
    XCTAssertTrue(centralManagerMock.cancelPeripheralConnectionCalled)
    XCTAssertTrue(centralManagerMock.canceledPeripherals.contains(peripheralMock))
    XCTAssertEqual(connectionManager.connectCalledCount, 1)
  }

  @MainActor func testDisconnectPeripheral_alreadyDisconnected_notifiesObserver() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)
    setPeripheralAssociated(peripheralMock)

    // Simulate a device being discovered and then connected to.
    connectionManager.centralManager(
      centralManagerMock, didDiscover: peripheralMock, advertisement: ["": ""], rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    // Introduce this type to avoid concurrency mutation errors.
    struct TestState {
      var disconnectedCarIdentifier: String? = nil
    }
    let testState = OSAllocatedUnfairLock(initialState: TestState())
    let observerCalledExpectation = XCTestExpectation(description: "Disconnection observer called")

    connectionManager.observeDisconnection { @Sendable _, car in
      testState.withLock {
        $0.disconnectedCarIdentifier = car.id
        observerCalledExpectation.fulfill()
      }
    }

    peripheralMock.state = .disconnected

    connectionManager.disconnect(peripheralMock)

    // Only a 2 second timeout since this call should happen immediately.
    wait(for: [observerCalledExpectation], timeout: 2.0)

    XCTAssertEqual(
      peripheralMock.identifier.uuidString,
      testState.withLock { $0.disconnectedCarIdentifier }
    )
  }

  @MainActor
  func testDisconnectPeripheral_alreadyDisconnectedButNotDiscovered_doesNotNotifyObserver() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)
    setPeripheralAssociated(peripheralMock)

    let observerCalledExpectation = XCTestExpectation(description: "Disconnection observer called")
    observerCalledExpectation.isInverted = true

    connectionManager.observeDisconnection { _, car in
      observerCalledExpectation.fulfill()
    }

    peripheralMock.state = .disconnected

    connectionManager.disconnect(peripheralMock)

    // Only a 2 second timeout since this call should happen immediately.
    wait(for: [observerCalledExpectation], timeout: 2.0)
  }

  @MainActor func testDisconnectPeripheral_callsScanForAssociatedDevices() {
    let peripheralMock = PeripheralMock(name: "associated")
    centralManagerMock.connectedPeripherals.insert(peripheralMock)
    setPeripheralAssociated(peripheralMock)

    // Simulate a device being discovered and then connected to.
    connectionManager.centralManager(
      centralManagerMock, didDiscover: peripheralMock, advertisement: ["": ""], rssi: 1.0)
    setUpValidConnection(for: peripheralMock)

    let scanForPeripheralsExpectation =
      XCTestExpectation(description: "Scan for peripherals expectation")
    centralManagerMock.scanForPeripheralsExpectation = scanForPeripheralsExpectation

    peripheralMock.state = .disconnected

    connectionManager.disconnect(peripheralMock)

    wait(for: [scanForPeripheralsExpectation], timeout: 2.0)

    XCTAssertEqual(centralManagerMock.servicesToScanFor?.count, 2)

    let servicesToScanFor = centralManagerMock.servicesToScanFor!
    XCTAssert(servicesToScanFor.contains(uuidConfig.reconnectionUUID(for: .v1)))
    XCTAssert(servicesToScanFor.contains(uuidConfig.reconnectionUUID(for: .v2)))
  }

  // MARK: - Renaming cars

  @MainActor func testRenameCar() {
    let associatedCar = PeripheralMock(name: "associated")
    setPeripheralAssociated(associatedCar)

    let newName = "newName"
    XCTAssertTrue(
      connectionManager.renameCar(withId: associatedCar.identifier.uuidString, to: newName))

    let expectedCar = Car(id: associatedCar.identifier.uuidString, name: newName)
    let updatedCar = connectionManager.associatedCars.first(where: { $0 == expectedCar })

    XCTAssertEqual(updatedCar?.name, newName)
  }

  @MainActor func testRenameCar_IgnoresNonAssociatedCar() {
    let carId = "carId"
    let newName = "newName"

    XCTAssertFalse(connectionManager.renameCar(withId: carId, to: newName))
    XCTAssert(connectionManager.associatedCars.isEmpty)
  }

  @MainActor func testRenameCar_IgnoresEmptyName() {
    let oldName = "oldName"
    let associatedCar = PeripheralMock(name: oldName)
    setPeripheralAssociated(associatedCar)

    XCTAssertFalse(connectionManager.renameCar(withId: associatedCar.identifier.uuidString, to: ""))

    let expectedCar = Car(id: associatedCar.identifier.uuidString, name: oldName)
    let updatedCar = connectionManager.associatedCars.first(where: { $0 == expectedCar })

    XCTAssertEqual(updatedCar?.name, oldName)
  }

  // MARK: - Helper functions.

  /// Runs through the reconnection flow for the given peripheral so that the connection manager
  /// will believe that it has a secure connection with it.
  @MainActor private func setUpValidConnection(for peripheral: PeripheralMock) {
    let backingCar = Car(id: peripheral.identifier.uuidString, name: peripheral.name)
    let communicationManager = makeCommunicationManager()

    //  First the device id needs to be exchanged for the peripheral
    connectionManager.communicationManager(
      communicationManager,
      establishingEncryptionWith: backingCar,
      peripheral: peripheral)

    let secureChannel = SecuredCarChannelMock(id: backingCar.id, name: backingCar.name)

    // Next a secure channel is established.
    connectionManager.communicationManager(
      makeCommunicationManager(),
      didEstablishSecureChannel: secureChannel)
  }

  /// Mocks the given peripheral as associated when the `ConnectionManager` queries for it.
  @MainActor private func setPeripheralAssociated(_ peripheral: PeripheralMock) {
    associatedCarsManager.addAssociatedCar(
      identifier: peripheral.identifier.uuidString,
      name: peripheral.name)
  }

  private func makeMockError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }

  @MainActor private func makeAssociationManagerMock() -> AssociationManager {
    return AssociationManager(
      overlay: Overlay(),
      connectionHandle: ConnectionHandleFake(),
      uuidConfig: UUIDConfig(plistLoader: PListLoaderFake()),
      associatedCarsManager: associatedCarsManager,
      secureSessionManager: SecureSessionManagerMock(),
      secureBLEChannel: SecureBLEChannelMock(),
      bleVersionResolver: versionResolverFake,
      outOfBandTokenProvider: FakeOutOfBandTokenProvider()
    )
  }

  @MainActor private func makeCommunicationManager() -> CommunicationManager {
    return CommunicationManager(
      overlay: Overlay(),
      connectionHandle: ConnectionHandleFake(),
      uuidConfig: UUIDConfig(plistLoader: PListLoaderFake()),
      associatedCarsManager: associatedCarsManager,
      secureSessionManager: SecureSessionManagerMock(),
      secureBLEChannelFactory: self,
      bleVersionResolver: BLEVersionResolverFake(),
      reconnectionHandlerFactory: ReconnectionHandlerFactoryFake()
    )
  }
}

// MARK: - secureBLEChannelFactory

extension ConnectionManagerTest: SecureBLEChannelFactory {
  func makeChannel() -> SecureBLEChannel {
    return SecureBLEChannelMock()
  }
}
