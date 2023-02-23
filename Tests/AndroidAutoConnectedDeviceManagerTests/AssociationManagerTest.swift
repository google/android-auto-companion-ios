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

import AndroidAutoConnectedDeviceManagerMocks
import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import AndroidAutoMessageStream
import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `AssociationManager`.
@MainActor class AssociationManagerTest: XCTestCase {
  private let associatedCarsManagerMock = AssociatedCarsManagerMock()
  private let secureSessionManagerMock = SecureSessionManagerMock()
  private let secureBLEChannelMock = SecureBLEChannelMock()
  private let messageHelperFactoryProxy = AssociationMessageHelperFactoryProxy()
  private let bleVersionResolverFake = BLEVersionResolverFake()

  // Valid mocks for happy path tests.
  private let clientWriteCharacteristicMock = CharacteristicMock(
    uuid: UUIDConfig.writeCharacteristicUUID,
    value: nil
  )

  private let serverWriteCharacteristicMock = CharacteristicMock(
    uuid: UUIDConfig.readCharacteristicUUID,
    value: nil
  )

  private var uuidConfig: UUIDConfig!
  private var connectionHandle: ConnectionHandleFake!
  private var validService: ServiceMock!

  // The manager under test.
  private var associationManager: AssociationManager!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    associatedCarsManagerMock.reset()
    secureSessionManagerMock.reset()
    secureBLEChannelMock.reset()
    messageHelperFactoryProxy.reset()

    // Characteristics have a default value of `nil` for their value.
    clientWriteCharacteristicMock.value = nil
    serverWriteCharacteristicMock.value = nil
    validService = ServiceMock(
      uuid: uuidConfig.associationUUID,
      characteristics: [clientWriteCharacteristicMock, serverWriteCharacteristicMock]
    )

    // Default state is to ensure that a secure channel is always set up.
    secureBLEChannelMock.establishShouldInstantlyNotify = true

    connectionHandle = ConnectionHandleFake()

    associationManager = AssociationManager(
      overlay: Overlay(),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannel: secureBLEChannelMock,
      bleVersionResolver: bleVersionResolverFake,
      outOfBandTokenProvider: FakeOutOfBandTokenProvider(),
      messageHelperFactory: messageHelperFactoryProxy
    )
  }

  /// Verify that a clean AssociationManager will return `false` for if an association has occurred.
  func testIsAssociated_falseWhenInitialized() {
    XCTAssertFalse(associationManager.isAssociated)
  }

  // MARK: - Association tests

  func testAssociatePeripheral_setsDelegateAndCallsDiscoverServices() {
    let peripheralMock = PeripheralMock(name: "name")
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )

    // Check that the association manager set itself to be the delegate.
    XCTAssert(peripheralMock.delegate === associationManager)
    XCTAssertTrue(peripheralMock.discoverServicesCalled)

    XCTAssertNotNil(peripheralMock.serviceUUIDs)
    XCTAssertEqual(peripheralMock.serviceUUIDs!.count, 1)
    XCTAssert(peripheralMock.serviceUUIDs!.contains(uuidConfig.associationUUID))
  }

  func testAssociatePeripheral_keepsStrongReferenceToPeripheral() {
    let peripheralMock = PeripheralMock(name: "name")
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )

    // AssociationManager needs to keep a strong reference to the car to be associated so that it
    // does not get deallocated too quickly.
    XCTAssert(associationManager.carToAssociate === peripheralMock)
  }

  func testAssociatePeripheral_doesNotAddToSuccessfulAssociation() {
    associationManager.associate(
      PeripheralMock(name: "name"),
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )

    XCTAssertTrue(associatedCarsManagerMock.identifiers.isEmpty)
    XCTAssertEqual(associatedCarsManagerMock.count, 0)
  }

  func testSetAssociationUUID_doesNotUseDefaultUUID() {
    let associationUUID = CBUUID(string: "dc14dbb3-7199-4aee-a63e-a76279977e4d")
    let peripheralMock = PeripheralMock(name: "name")
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: associationUUID)
    )

    // Check that the association manager set itself to be the delegate.
    XCTAssert(peripheralMock.delegate === associationManager)
    XCTAssertTrue(peripheralMock.discoverServicesCalled)

    XCTAssertNotNil(peripheralMock.serviceUUIDs)
    XCTAssertEqual(peripheralMock.serviceUUIDs!.count, 1)
    XCTAssert(peripheralMock.serviceUUIDs!.contains(associationUUID))
  }

  // MARK: - clearAssociation tests

  func testClearAllAssociations_clearsReferenceToPeripheral() {
    let peripheralMock = PeripheralMock(name: "name")

    // Associate to set the reference.
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )
    XCTAssertNotNil(associationManager.carToAssociate)

    // Now, call clearAssociation() and check that the reference is cleared.
    associationManager.clearAllAssociations()
    XCTAssertNil(associationManager.carToAssociate)
  }

  func testClearCurrentAssociation_clearsReferenceToPeripheral() {
    let peripheralMock = PeripheralMock(name: "name")

    // Associate to set the reference.
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )
    XCTAssertNotNil(associationManager.carToAssociate)

    // Now, call clearAssociation() and check that the reference is cleared.
    associationManager.clearCurrentAssociation()
    XCTAssertNil(associationManager.carToAssociate)
  }

  func testClearAllAssociations_clearsIdentifier() {
    // Set an identifier on the ConnectCarManager.
    addAssociatedCar(Car(id: "fake1", name: "fake-name"))

    // Now, call clearAssociation() and check that the identifier is cleared.
    associationManager.clearAllAssociations()
    XCTAssertEqual(associatedCarsManagerMock.identifiers.count, 0)
  }

  func testClearAllAssociations_clearsSecureSessions() {
    addAssociatedCar(Car(id: "fake1", name: "fake-name"))
    addAssociatedCar(Car(id: "fake2", name: "fake-name"))

    // Now, call clearAssociation() and verify all secure sessions cleared.
    associationManager.clearAllAssociations()
    XCTAssertEqual(secureSessionManagerMock.secureSessions.count, 0)
  }

  func testClearAllAssociations_clearsMultiple() {
    addAssociatedCar(Car(id: "fake1", name: "fake-name1"))
    addAssociatedCar(Car(id: "fake2", name: "fake-name2"))

    associationManager.clearAllAssociations()
    XCTAssertEqual(associatedCarsManagerMock.identifiers.count, 0)
  }

  func testClearAssociation_clearsExisting() {
    let car1 = Car(id: "fake1", name: "fake-name1")
    let car2 = Car(id: "fake2", name: "fake-name2")
    addAssociatedCar(car1)
    addAssociatedCar(car2)

    associationManager.clearAssociation(for: car1)
    XCTAssertEqual(associatedCarsManagerMock.identifiers.count, 1)
    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(car2.id))
  }

  func testClearAssociation_clearsExistingSecureSession() {
    let car1 = Car(id: "fake1", name: "fake-name1")
    let car2 = Car(id: "fake2", name: "fake-name2")
    addAssociatedCar(car1)
    addAssociatedCar(car2)

    associationManager.clearAssociation(for: car1)
    XCTAssertEqual(secureSessionManagerMock.secureSessions.count, 1)
    XCTAssertNotNil(secureSessionManagerMock.secureSessions[car2.id])
  }

  func testClearAssociation_doesNotExist_doesNothing() {
    let car1 = Car(id: "fake1", name: "fake-name1")
    let car2 = Car(id: "fake2", name: "fake-name2")
    addAssociatedCar(car1)

    associationManager.clearAssociation(for: car2)
    XCTAssertEqual(associatedCarsManagerMock.identifiers.count, 1)
  }

  func testClearAssociation_doesNotExist_doesNotClearSecureSession() {
    let car1 = Car(id: "fake1", name: "fake-name1")
    let car2 = Car(id: "fake2", name: "fake-name2")
    addAssociatedCar(car1)

    associationManager.clearAssociation(for: car2)
    XCTAssertEqual(secureSessionManagerMock.secureSessions.count, 1)
    XCTAssertNotNil(secureSessionManagerMock.secureSessions[car1.id])
  }

  // MARK: - discoverServices tests

  func testDiscoverServices_withErrorCallsDelegateWithError() {
    let delegate = AssociationDelegateMock()

    associationManager.delegate = delegate
    associationManager.peripheral(
      PeripheralMock(name: "mock", services: nil),
      didDiscoverServices: makeFakeError()
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverServices)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverServices_withNilServicesCallsDelegateWithError() {
    let delegate = AssociationDelegateMock()

    associationManager.delegate = delegate
    associationManager.peripheral(
      PeripheralMock(name: "mock", services: nil),
      didDiscoverServices: nil
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverServices)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverServices_withNoServicesCallsDelegateWithError() {
    let delegate = AssociationDelegateMock()

    associationManager.delegate = delegate
    associationManager.peripheral(
      PeripheralMock(name: "mock", services: []),
      didDiscoverServices: nil
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverServices)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverServices_withAssociationServicesCallsDiscoverCharacteristics() {
    let mockServiceWithAssociation = ServiceMock(uuid: uuidConfig.associationUUID)
    let peripheralMock = PeripheralMock(name: "mock", services: [mockServiceWithAssociation])

    associationManager.peripheral(peripheralMock, didDiscoverServices: nil)

    XCTAssertTrue(peripheralMock.discoverCharacteristicsCalled)
  }

  func testDiscoverServices_withNonAssociationServicesDoesNotCallDiscoverCharacteristics() {
    // Create a service with the wrong UUID.
    let mockServiceWithoutAssociation = ServiceMock(uuid: CBUUID(string: "bad1"))
    let peripheralMock = PeripheralMock(name: "mock", services: [mockServiceWithoutAssociation])

    associationManager.peripheral(peripheralMock, didDiscoverServices: nil)

    XCTAssertFalse(peripheralMock.discoverCharacteristicsCalled)
  }

  func testDiscoverServices_timedOut_notifiesDelegateOfError() {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    associationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let peripheralMock = PeripheralMock(name: "name")
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )

    // `didDiscoverServices` is not invoked, so the association should time out.
    delegate.errorExpectation = expectation(description: "Delegate notified with error.")

    waitForExpectations(timeout: associationManager.timeoutDuration.toSeconds())
    XCTAssertEqual(delegate.error, .timedOut)
  }

  // MARK: - didDiscoverCharacteristics tests

  func testDiscoverCharacteristics_withErrorCallsDelegateWithError() {
    let fakeError = makeFakeError()
    let delegate = AssociationDelegateMock()
    let serviceMock = ServiceMock(uuid: CBUUID(string: "bad1"), characteristics: nil)

    associationManager.delegate = delegate
    associationManager.peripheral(
      PeripheralMock(name: "mock", services: nil),
      didDiscoverCharacteristicsFor: serviceMock,
      error: fakeError
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverCharacteristics)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverCharacteristics_withNilCharacteristicsCallsDelegateWithError() {
    let delegate = AssociationDelegateMock()

    let serviceMock = ServiceMock(uuid: CBUUID(string: "bad1"), characteristics: nil)
    let peripheralMock = PeripheralMock(name: "mock", services: [serviceMock])

    associationManager.delegate = delegate
    associationManager.peripheral(
      peripheralMock,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverCharacteristics)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverCharacteristics_withNoCharacteristicsCallsDelegateWithError() {
    let delegate = AssociationDelegateMock()

    let serviceMock = ServiceMock(uuid: CBUUID(string: "bad1"), characteristics: [])
    let peripheralMock = PeripheralMock(name: "mock", services: [serviceMock])

    associationManager.delegate = delegate
    associationManager.peripheral(
      peripheralMock,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverCharacteristics)

    // Verify association reported as unsuccessful.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverCharacteristics_missingReadCharacteristic() {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    // Missing read characteristic.
    let serviceMock = ServiceMock(
      uuid: uuidConfig.associationUUID,
      characteristics: [serverWriteCharacteristicMock]
    )
    let peripheralMock = PeripheralMock(name: "mock", services: [serviceMock])

    associationManager.peripheral(
      peripheralMock,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Delegate should still be called to be notified of error
    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverCharacteristics)

    // Verify association still not complete at this point.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverCharacteristics_missingWriteCharacteristic() {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    // Missing write characteristic.
    let serviceMock = ServiceMock(
      uuid: uuidConfig.associationUUID,
      characteristics: [clientWriteCharacteristicMock]
    )
    let peripheralMock = PeripheralMock(name: "mock", services: [serviceMock])

    associationManager.peripheral(
      peripheralMock,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Delegate should still be called to be notified of error
    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotDiscoverCharacteristics)

    // Verify association still not complete at this point.
    XCTAssertFalse(associationManager.isAssociated)
  }

  func testDiscoverCharacteristics_timedOut_notifiesDelegateOfError() {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate
    associationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    associationManager.associate(
      peripheralMock,
      config: AssociationConfig(associationUUID: uuidConfig.associationUUID)
    )

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    delegate.errorExpectation = expectation(description: "Delegate notified with error.")

    waitForExpectations(timeout: associationManager.timeoutDuration.toSeconds())
    XCTAssertEqual(delegate.error, .timedOut)
  }

  // MARK: - Message helper calls.

  func testMessageHelperCalls_startCalled() {
    messageHelperFactoryProxy.shouldUseRealFactory = false

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let messageHelperMock =
      messageHelperFactoryProxy.latestMessageHelper
      as! AssociationMessageHelperMock

    XCTAssertTrue(messageHelperMock.startCalled)
  }

  func testMessageHelperCalls_handleMessageCalled() {
    messageHelperFactoryProxy.shouldUseRealFactory = false

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    // Next, send any message
    let data = Data("Test".utf8)
    associationManager.messageStream(
      associationManager.messageStream!,
      didReceiveMessage: data,
      params: MessageStreamParams(
        recipient: UUID(),
        operationType: .encryptionHandshake
      )
    )

    let messageHelperMock =
      messageHelperFactoryProxy.latestMessageHelper
      as! AssociationMessageHelperMock
    XCTAssertTrue(messageHelperMock.handleMessageCalled)
  }

  func testMessageHelperCalls_encryptionAndPairingFlow() {
    messageHelperFactoryProxy.shouldUseRealFactory = false

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let messageHelperMock =
      messageHelperFactoryProxy.latestMessageHelper
      as! AssociationMessageHelperMock

    messageHelperMock.performEncryptionAndPairingFlow()

    XCTAssertTrue(messageHelperMock.onPairingCodeDisplayedCalled)
    XCTAssertTrue(messageHelperMock.onEncryptionEstablishedCalled)
    XCTAssertTrue(delegate.receivedCarIdCalled)
    XCTAssertTrue(delegate.requiresDisplayOfPairingCodeCalled)
  }

  func testMessageHelperCalls_messageDidSendSuccessfullyCalled() {
    messageHelperFactoryProxy.shouldUseRealFactory = false

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    notifyMessageSentSuccessfully(to: UUID())

    let messageHelperMock =
      messageHelperFactoryProxy.latestMessageHelper
      as! AssociationMessageHelperMock
    XCTAssertTrue(messageHelperMock.messageDidSendSuccessfullyCalled)
  }

  // MARK: - Pairing code tests.

  func testPairingCode_pairingCodeRejected_securityV1() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v1

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    XCTAssert(peripheralMock.characteristicToNotifyFor === serverWriteCharacteristicMock)

    notifyMessageSentSuccessfully(to: UUID())

    let identifier = makeRandomUUID()
    sendCarId(identifier, to: associationManager)

    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)

    // Next, send the wrong pairing code
    let data = Data("False".utf8)
    associationManager.messageStream(
      associationManager.messageStream!,
      didReceiveMessage: data,
      params: MessageStreamParams(
        recipient: UUID(),
        operationType: .encryptionHandshake
      )
    )

    XCTAssertFalse(secureBLEChannelMock.notifyPairingCodeAcceptedCalled)

    // Verify that write value is not called again.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .pairingCodeRejected)
  }

  func testPairingCode_doesNotTimeOut() {
    let delegate = AssociationDelegateMock()

    associationManager.delegate = delegate
    associationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    messageHelperFactoryProxy.shouldUseRealFactory = false

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let messageHelperMock =
      messageHelperFactoryProxy.latestMessageHelper
      as! AssociationMessageHelperMock

    XCTAssertTrue(messageHelperMock.startCalled)

    // Next, send any message
    let data = Data("Test".utf8)
    associationManager.messageStream(
      associationManager.messageStream!,
      didReceiveMessage: data,
      params: MessageStreamParams(
        recipient: UUID(),
        operationType: .encryptionHandshake
      )
    )

    messageHelperMock.performEncryptionFlow()

    // Car does not send response that pairing code is confirmed, but verify it does not time
    // out.
    delegate.errorExpectation = expectation(description: "Delegate notified with error.")
    delegate.errorExpectation?.isInverted = true

    waitForExpectations(timeout: associationManager.timeoutDuration.toSeconds())
    XCTAssertFalse(delegate.didEncounterErrorCalled)
  }

  // MARK - BLEMessageStream error test

  func testBleMessageStreamError_notifiesDelegate() {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    // Note: valid characteristics are needed for a valid BLEMessageStream to be created.
    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let messageStream = associationManager.messageStream!
    associationManager.messageStreamEncounteredUnrecoverableError(messageStream)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .unknown)
  }

  // MARK: - Test storage of secure session.

  func testSaveSecureSession_notifiesDelegateIfSaveFailed_securityV1() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v1

    // Ensure that saving the secure session will not succeed.
    secureBLEChannelMock.saveSessionSucceeds = false

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    // The phone sends it device id first, so acknowledge that it was successful.
    notifyMessageSentSuccessfully(to: UUID())

    let identifier = makeRandomUUID()
    sendCarId(identifier, to: associationManager)
    sendPairingCodeConfirmation(to: associationManager)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotStoreAssociation)
  }

  func testSaveSecureSession_notifiesDelegateIfSaveFailed_securityV2() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v2

    // Ensure that saving the secure session will not succeed.
    secureBLEChannelMock.saveSessionSucceeds = false

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let identifier = makeRandomUUID()
    sendCarId(identifier, to: associationManager)

    // The save happens after we confirm that the phone responds with device id + authentication
    // key.
    notifyMessageSentSuccessfully(to: UUID())

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .cannotStoreAssociation)
  }

  func testSaveSecureSession_savedAfterAssociation_securityV1() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v1

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    // The phone responds with its device id, so acknowledge that the send was successful.
    notifyMessageSentSuccessfully(to: UUID())

    let identifier = makeRandomUUID()
    sendCarId(identifier, to: associationManager)
    sendPairingCodeConfirmation(to: associationManager)

    // Verify that a secure session has been saved.
    XCTAssertEqual(
      try! secureBLEChannelMock.saveSession(),
      secureSessionManagerMock.secureSession(for: identifier.uuidString)
    )
  }

  func testSaveSecureSession_savedAfterAssociation_securityV2() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v2

    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    let identifier = makeRandomUUID()
    sendCarId(identifier, to: associationManager)

    // The save happens after we confirm that the phone responds with device id + authentication
    // key.
    notifyMessageSentSuccessfully(to: UUID())

    // Verify that a secure session has been saved.
    XCTAssertEqual(
      try! secureBLEChannelMock.saveSession(),
      secureSessionManagerMock.secureSession(for: identifier.uuidString)
    )
  }

  // MARK: - Association complete tests

  func testAssociationComplete_securityV1() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v1

    let identifier = makeRandomUUID()
    associatePeripheral_securityV1(withIdentifier: identifier)
    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier.uuidString))
  }

  func testAssociationComplete_securityV2() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v2

    let identifier = makeRandomUUID()
    associatePeripheral_securityV2(withIdentifier: identifier)
    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier.uuidString))
  }

  func testAssociationComplete_multipleDevices_securityV1() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v1

    let identifier1 = makeRandomUUID()
    let identifier2 = makeRandomUUID()
    associatePeripheral_securityV1(withIdentifier: identifier1)

    // reset everything except associatedCarsManager, which stores previous associations
    secureSessionManagerMock.reset()
    secureBLEChannelMock.reset()
    secureBLEChannelMock.establishShouldInstantlyNotify = true
    associationManager = AssociationManager(
      overlay: Overlay(),
      connectionHandle: ConnectionHandleFake(),
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannel: secureBLEChannelMock,
      bleVersionResolver: bleVersionResolverFake,
      outOfBandTokenProvider: FakeOutOfBandTokenProvider()
    )

    associatePeripheral_securityV1(withIdentifier: identifier2)

    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier1.uuidString))
    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier2.uuidString))
    XCTAssertEqual(associatedCarsManagerMock.count, 2)
  }

  func testAssociationComplete_multipleDevices_securityV2() {
    messageHelperFactoryProxy.shouldUseRealFactory = true
    bleVersionResolverFake.securityVersion = .v2

    let identifier1 = makeRandomUUID()
    let identifier2 = makeRandomUUID()
    associatePeripheral_securityV2(withIdentifier: identifier1)

    // reset everything except associatedCarsManager, which stores previous associations
    secureSessionManagerMock.reset()
    secureBLEChannelMock.reset()
    secureBLEChannelMock.establishShouldInstantlyNotify = true
    associationManager = AssociationManager(
      overlay: Overlay(),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannel: secureBLEChannelMock,
      bleVersionResolver: bleVersionResolverFake,
      outOfBandTokenProvider: FakeOutOfBandTokenProvider()
    )

    associatePeripheral_securityV2(withIdentifier: identifier2)

    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier1.uuidString))
    XCTAssertTrue(associatedCarsManagerMock.identifiers.contains(identifier2.uuidString))
    XCTAssertEqual(associatedCarsManagerMock.count, 2)
  }

  /// Associates a peripheral with the provided `identifier` and tests that association was
  /// successful. Follows the security version 1 flow.
  private func associatePeripheral_securityV1(withIdentifier identifier: CBUUID) {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    XCTAssert(peripheralMock.characteristicToNotifyFor === serverWriteCharacteristicMock)

    // The phone sends its device id first, so acknowledge that it is successful.
    notifyMessageSentSuccessfully(to: UUID())

    sendCarId(identifier, to: associationManager)

    // The association manager should be storing the id that it received.
    XCTAssertEqual(associationManager.carId, identifier.uuidString)
    XCTAssertEqual(1, peripheralMock.writeValueCalledCount)

    sendPairingCodeConfirmation(to: associationManager)

    // Association is now complete.
    XCTAssertTrue(delegate.didCompleteAssociationCalled)
    XCTAssertEqual(delegate.associatedCar!.id, identifier.uuidString)
    XCTAssert(delegate.associatedPeripheral === peripheralMock)

    XCTAssertTrue(associationManager.isAssociated)
  }

  /// Associates a peripheral with the provided `identifier` and tests that association was
  /// successful. Follows the sercurity version 2 flow.
  private func associatePeripheral_securityV2(withIdentifier identifier: CBUUID) {
    let delegate = AssociationDelegateMock()
    associationManager.delegate = delegate

    let peripheralMock = PeripheralMock(name: "mock", services: [validService])

    notifyValidCharacteristicsDiscovered(for: peripheralMock)

    XCTAssert(peripheralMock.characteristicToNotifyFor === serverWriteCharacteristicMock)
    XCTAssertNotNil(associationManager.messageStream)

    sendCarId(identifier, to: associationManager)

    // The phone responds with its device id + authentication key, so acknowledge that the message
    // send was successful.
    notifyMessageSentSuccessfully(to: UUID())

    // The association manager should be storing the id that it received, but in version 2 sending
    // the id completes the association and thus resets the association manager.
    XCTAssertEqual(1, peripheralMock.writeValueCalledCount)

    // Association is now complete.
    XCTAssertTrue(delegate.didCompleteAssociationCalled)
    XCTAssertEqual(delegate.associatedCar!.id, identifier.uuidString)
    XCTAssert(delegate.associatedPeripheral === peripheralMock)

    XCTAssertTrue(associationManager.isAssociated)
  }

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }

  private func makeRandomUUID() -> CBUUID {
    return CBUUID(string: UUID().uuidString)
  }

  // MARK: - Convenience functions.

  // Methods that wrap callbacks for messages sent from the car to phone. These methods are all
  // for happy path testing.

  /// Simulates that valid characteristics have been discovered for the given peripheral.
  ///
  /// Valid characteristics means that it contains the correct UUIDs for a server write
  /// and a client read characteristics.
  private func notifyValidCharacteristicsDiscovered(for peripheral: BLEPeripheral) {
    associationManager.peripheral(
      peripheral,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )
  }

  /// Simulates the car sending its car id to the given association manager.
  private func sendCarId(_ carId: CBUUID, to associationManager: AssociationManager) {
    associationManager.messageStream(
      associationManager.messageStream!,
      didReceiveMessage: carId.data,
      params: MessageStreamParams(
        recipient: UUID(),
        operationType: .encryptionHandshake
      )
    )
  }

  /// Simulates the car sending confirmation that the user has confirmed the pairing code.
  private func sendPairingCodeConfirmation(to associationManager: AssociationManager) {
    associationManager.messageStream(
      associationManager.messageStream!,
      didReceiveMessage: Data(AssociationManager.pairingCodeConfirmationValue.utf8),
      params: MessageStreamParams(
        recipient: UUID(),
        operationType: .encryptionHandshake
      )
    )
  }

  /// Simulates the given car as being associated.
  private func addAssociatedCar(_ car: Car) {
    associatedCarsManagerMock.addAssociatedCar(identifier: car.id, name: car.name)
    let _ = secureSessionManagerMock.storeSecureSession(Data(), for: car.id)
  }

  /// Invokes a callback on the `associationManager` acknowledging that a message was just
  /// successfully sent to the recipient with the given `UUID`.
  private func notifyMessageSentSuccessfully(to recipient: UUID) {
    associationManager.messageStreamDidWriteMessage(
      associationManager.messageStream!, to: recipient)
  }
}

// MARK: - Mocks

/// A mock `AssociationManagerDelegate` that can assert if its `onAssociationComplete` method was
/// called and with what value.
class AssociationDelegateMock: AssociationManagerDelegate {
  var didCompleteAssociationCalled = false
  var associatedCar: Car? = nil
  var associatedPeripheral: BLEPeripheral? = nil

  var receivedCarIdCalled = false
  var requiresDisplayOfPairingCodeCalled = false
  var pairingCode: String?

  var didEncounterErrorCalled = false
  var error: AssociationError? = nil
  var errorExpectation: XCTestExpectation? = nil

  func associationManager(
    _ associationManager: AssociationManager,
    didCompleteAssociationWithCar car: Car,
    securedCarChannel: SecuredConnectedDeviceChannel,
    peripheral: BLEPeripheral
  ) {
    didCompleteAssociationCalled = true
    associatedCar = car
    associatedPeripheral = peripheral
  }

  func associationManager(
    _ associationManager: AssociationManager, didReceiveCarId carId: String
  ) {
    receivedCarIdCalled = true
  }

  func associationManager(
    _ associationManager: AssociationManager,
    requiresDisplayOf pairingCode: String
  ) {
    requiresDisplayOfPairingCodeCalled = true
    self.pairingCode = pairingCode
  }

  func associationManager(
    _ associationManager: AssociationManager,
    didEncounterError error: Error
  ) {
    didEncounterErrorCalled = true

    guard let associationError = error as? AssociationError else {
      XCTFail("Error received from delegate is not of type AssociationError")
      return
    }

    self.error = associationError
    errorExpectation?.fulfill()
  }
}

/// Fake Out-Of-Band Token Provider.
class FakeOutOfBandTokenProvider: OutOfBandTokenProvider {
  private var completion: ((OutOfBandToken?) -> Void)?
  private var token: OutOfBandToken? = nil

  func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
    if let token = token {
      completion(token)
    } else {
      self.completion = completion
    }
  }

  func reset() {
    token = nil
    completion?(nil)
    completion = nil
  }

  func postToken(_ token: OutOfBandToken?) {
    self.token = token
    completion?(token)
    completion = nil
  }

  init() {}
}
