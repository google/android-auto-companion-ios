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
import AndroidAutoSecureChannel
import CoreBluetooth
import XCTest
import AndroidAutoTrustAgentProtos

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `CommunicationManager`. Specifically testing the version 2 flow.

@MainActor class CommunicationManagerTest: XCTestCase {
  private let associatedCarsManagerMock = AssociatedCarsManagerMock()
  private let secureSessionManagerMock = SecureSessionManagerMock()
  private let reconnectionHandlerFactory = ReconnectionHandlerFactoryFake()

  private let ioCharactersticsUUIDs = CommunicationManager.versionCharacteristics

  // Valid mocks for happy path testing.
  private var writeCharacteristicMock: CharacteristicMock!
  private var readCharacteristicMock: CharacteristicMock!
  private var advertisementCharacteristicMock: CharacteristicMock!

  private var validService: ServiceMock!

  private var connectionHandle: ConnectionHandleFake!

  private var delegate: CommunicationManagerDelegateFake!
  private var bleVersionResolver: BLEVersionResolverFake!
  private var communicationManager: CommunicationManager!
  private var reconnectionHelpers: [UUID: ReconnectionHelperMock]!
  private var uuidConfig: UUIDConfig!

  override func setUp() async throws {
    try await super.setUp()

    reconnectionHelpers = [:]

    writeCharacteristicMock = CharacteristicMock(
      uuid: ioCharactersticsUUIDs.writeUUID,
      value: nil
    )

    readCharacteristicMock = CharacteristicMock(
      uuid: ioCharactersticsUUIDs.readUUID,
      value: nil
    )

    advertisementCharacteristicMock = CharacteristicMock(
      uuid: CommunicationManager.advertisementCharacteristicUUID,
      value: Data("testAd".utf8)
    )

    continueAfterFailure = false

    associatedCarsManagerMock.reset()
    secureSessionManagerMock.reset()
    reconnectionHandlerFactory.reset()

    uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())

    // Characteristics have a default value of `nil` for their value.
    writeCharacteristicMock.value = nil
    readCharacteristicMock.value = nil
    validService = ServiceMock(
      uuid: uuidConfig.reconnectionUUID(for: .v1),
      characteristics: [
        writeCharacteristicMock, readCharacteristicMock, advertisementCharacteristicMock,
      ]
    )

    bleVersionResolver = BLEVersionResolverFake()
    connectionHandle = ConnectionHandleFake()
    communicationManager = CommunicationManager(
      overlay: Overlay(),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannelFactory: self,
      bleVersionResolver: bleVersionResolver,
      reconnectionHandlerFactory: reconnectionHandlerFactory)

    delegate = CommunicationManagerDelegateFake()
    communicationManager.delegate = delegate
  }

  override func tearDown() {
    reconnectionHelpers = nil

    super.tearDown()
  }

  // MARK: - Version Resolution Tests

  func testVersionResolution_noPendingCar_notifiesDelegate() {
    let car = PeripheralMock(name: "name")

    // Calling version resolution without a call to `setupSecureChannel`.
    communicationManager.bleVersionResolver(
      bleVersionResolver,
      didResolveStreamVersionTo: .passthrough,
      securityVersionTo: .v1,
      for: car
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testVersionResolution_noCharacteristics_notifiesDelegate() {
    let car = PeripheralMock(name: "name")

    let helper = ReconnectionHelperV1(peripheral: car)
    communicationManager.addReconnectionHelper(helper)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // Calling version resolution without characteristics being discovered.
    communicationManager.bleVersionResolver(
      bleVersionResolver,
      didResolveStreamVersionTo: .passthrough,
      securityVersionTo: .v1,
      for: car
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testVersionResolver_throwsError_notifiesDelegate() {
    let car = PeripheralMock(name: "name")

    communicationManager.bleVersionResolver(
      bleVersionResolver,
      didEncounterError: .emptyResponse,  // Any error except versionNotSupported.
      for: car
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
    XCTAssert(delegate.error == .versionResolutionFailed)
  }

  func testVersionResolver_versionNotSupported_notifiesDelegate() {
    let car = PeripheralMock(name: "name")

    communicationManager.bleVersionResolver(
      bleVersionResolver,
      didEncounterError: .versionNotSupported,
      for: car
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
    XCTAssert(delegate.error == .versionNotSupported)
  }

  // MARK: - setUpSecureChannel Tests

  func testSetUpSecureChannel_withNoId_DiscoversServices_forV1() {
    let id = "id"
    let car = PeripheralMock(name: "name")

    setUpAssociatedCar(id: id, car: car)

    let helper = ReconnectionHelperV1(peripheral: car)
    communicationManager.addReconnectionHelper(helper)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // This should kick off a discover services call.
    XCTAssert(car.delegate === communicationManager)
    XCTAssertTrue(car.discoverServicesCalled)

    // Check that the service UUID to discover matches the v1 UUID.
    XCTAssertNotNil(car.serviceUUIDs)
    XCTAssertEqual(car.serviceUUIDs!.count, 1)
    XCTAssert(car.serviceUUIDs!.contains(uuidConfig.reconnectionUUID(for: .v1)))
  }

  func testEstablishEncryption_happyPath() {
    // Car ID messsage should be a valid UUID.
    let message = Data("0123456789ABCDEF".utf8)
    let carID = CBUUID(data: message).uuidString
    let car = PeripheralMock(name: "name")

    setUpAssociatedCar(id: carID, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // PendingCar is only created after characteristics are discovered.
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let helper = ReconnectionHelperV1(peripheral: car)
    communicationManager.addReconnectionHelper(helper)

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    XCTAssertFalse(delegate.didEncounterErrorCalled)
  }

  func testEstablishEncryption_noSavedEncryption_notifiesDelegate() {
    let carID = "id"
    let car = PeripheralMock(name: "name")

    setUpAssociatedCar(id: carID, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // PendingCar is only created after characteristics are discovered.
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let helper = ReconnectionHelperV1(peripheral: car)
    communicationManager.addReconnectionHelper(helper)

    // Messsage should be a valid UUID.
    let message = Data("0123456789ABCDEF".utf8)  // Mismatches carID.

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
    XCTAssert(delegate.error == .noSavedEncryption)
  }

  func testEstablishEncryption_invalidSavedEncryption_notifiesDelegate() {
    // Car ID messsage should be a valid UUID.
    let message = Data("0123456789ABCDEF".utf8)
    let carID = CBUUID(data: message).uuidString
    let car = PeripheralMock(name: "name")

    setUpAssociatedCar(id: carID, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // PendingCar is only created after characteristics are discovered.
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let helper = ReconnectionHelperV1(peripheral: car)
    communicationManager.addReconnectionHelper(helper)

    // Force encryption failure.
    reconnectionHandlerFactory.makeChannelEstablishEncryptionShouldFail = true

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
    XCTAssert(delegate.error == .failedEncryptionEstablishment)
  }

  // MARK: - Discover services tests.

  func testDiscoverServices_withErrorDoesNotDiscoverCharacteristics() {
    let fakeError = makeMockError()
    let car = PeripheralMock(name: "mock", services: nil)

    communicationManager.peripheral(car, didDiscoverServices: fakeError)

    XCTAssertFalse(car.discoverCharacteristicsCalled)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverServices_withNilServicesDoesNotDiscoverCharacteristics() {
    let car = PeripheralMock(name: "mock", services: nil)

    communicationManager.peripheral(car, didDiscoverServices: nil)

    XCTAssertFalse(car.discoverCharacteristicsCalled)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverServices_withNoServicesDoesNotDiscoverCharacteristics() {
    let car = PeripheralMock(name: "mock", services: [])

    communicationManager.peripheral(car, didDiscoverServices: nil)

    XCTAssertFalse(car.discoverCharacteristicsCalled)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverServices_withUnlockServicesCallsDiscoverCharacteristics() {
    let mockService = ServiceMock(uuid: uuidConfig.reconnectionUUID(for: .v1))
    let car = PeripheralMock(name: "mock", services: [mockService])

    communicationManager.peripheral(car, didDiscoverServices: nil)

    XCTAssertTrue(car.discoverCharacteristicsCalled)
    XCTAssert(mockService === car.serviceToDiscoverFor)

    XCTAssertNotNil(car.characteristicUUIDs)
    XCTAssertEqual(car.characteristicUUIDs!.count, 3)
    XCTAssert(car.characteristicUUIDs!.contains(readCharacteristicMock.uuid))
    XCTAssert(car.characteristicUUIDs!.contains(writeCharacteristicMock.uuid))
    XCTAssert(car.characteristicUUIDs!.contains(advertisementCharacteristicMock.uuid))
  }

  func testDiscoverServices_timedOut_notifiesDelegateOfError() {
    communicationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let car = PeripheralMock(name: "name", services: [validService])

    setUpAssociatedCar(id: "id", car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    delegate.errorExpectation = expectation(description: "Delegate notified with error.")

    waitForExpectations(timeout: communicationManager.timeoutDuration.toSeconds())
    XCTAssertEqual(delegate.error, .failedEncryptionEstablishment)
  }

  // MARK: - Discover characteristics tests.

  func testDiscoverCharacteristics_withErrorDoesNotSendDeviceID() {
    let id = "id"
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: makeMockError()
    )

    // Verify no device id written.
    XCTAssertEqual(car.writtenData.count, 0)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverCharacteristics_withNoCharacteriticsDoesNotSendDeviceID() {
    let id = "id"
    let name = "name"
    let serviceMock = ServiceMock(
      uuid: uuidConfig.reconnectionUUID(for: .v1), characteristics: nil)
    let car = PeripheralMock(name: name, services: [serviceMock])

    setUpAssociatedCar(id: id, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Verify no device id written.
    XCTAssertEqual(car.writtenData.count, 0)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverCharacteristics_withWrongUUIDDoesNotSendDeviceID() {
    let id = "id"
    let name = "name"

    // Wrong UUIDs for the characteristics.

    let badWriteCharacteristic = CharacteristicMock(
      uuid: CBUUID(string: "bad2"),
      value: nil
    )

    let badReadCharacteristicMock = CharacteristicMock(
      uuid: CBUUID(string: "bad3"),
      value: nil
    )

    let serviceMock = ServiceMock(
      uuid: CBUUID(string: "bad1"),
      characteristics: [badWriteCharacteristic, badReadCharacteristicMock]
    )
    let car = PeripheralMock(name: name, services: [serviceMock])

    setUpAssociatedCar(id: id, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Verify no device id written.
    XCTAssertEqual(car.writtenData.count, 0)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverCharacteristics_missingClientWriteCharacteristicDoesNotSendDeviceID() {
    let id = "id"
    let name = "name"

    // Missing clientWriteCharacteristic.
    let serviceMock = ServiceMock(
      uuid: uuidConfig.reconnectionUUID(for: .v1),
      characteristics: [writeCharacteristicMock]
    )
    let car = PeripheralMock(name: name, services: [serviceMock])

    setUpAssociatedCar(id: id, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Verify no device id written.
    XCTAssertEqual(car.writtenData.count, 0)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  func testDiscoverCharacteristics_missingServerWriteCharacteristicDoesNotSendDeviceID() {
    let id = "id"
    let name = "name"

    // Missing serverWriteCharacteristic.
    let serviceMock = ServiceMock(
      uuid: uuidConfig.reconnectionUUID(for: .v1),
      characteristics: [readCharacteristicMock]
    )
    let car = PeripheralMock(name: name, services: [serviceMock])

    setUpAssociatedCar(id: id, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: serviceMock,
      error: nil
    )

    // Verify no device id written.
    XCTAssertEqual(car.writtenData.count, 0)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssert(delegate.peripheralWithError === car)
  }

  // MARK: - BLEMessageStream error test.

  func testBLEMessageStream_unrecoverableError_disconnects() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // PendingCar is only created after characteristics are discovered.
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let messageStream = pendingCar.messageStream!
    communicationManager.messageStreamEncounteredUnrecoverableError(messageStream)

    XCTAssertTrue(connectionHandle.disconnectCalled)
    XCTAssert(messageStream === connectionHandle.disconnectedStream)
  }

  func testReconnectionHandshakeFails_NoSecureChannel() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let reconnectionHelper = reconnectionHelpers[car.identifier]!
    reconnectionHelper.shouldThrowInvalidMessage = true

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: Data("Test".utf8),
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    XCTAssertTrue(reconnectionHelper.handleMessageCalled)

    // Secure channel should not have been created.
    XCTAssertEqual(reconnectionHandlerFactory.createdChannels.count, 0)
  }

  func testDiscoverCharacteristics_timedOut_notifiesDelegateOfError() {
    communicationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let car = PeripheralMock(name: "name", services: [validService])

    setUpAssociatedCar(id: "id", car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))
    communicationManager.peripheral(car, didDiscoverServices: nil)

    delegate.errorExpectation = expectation(description: "Delegate notified with error.")

    waitForExpectations(timeout: communicationManager.timeoutDuration.toSeconds())
    XCTAssertEqual(delegate.error, .failedEncryptionEstablishment)
  }

  // MARK: - Encryption setup failure tests.

  func testEncryptionSetupTimedOut_notifiesDelegate() {
    communicationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    // Characteristics discovered, but no response from the car.
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    delegate.errorExpectation = expectation(description: "Delegate notified with error.")

    waitForExpectations(timeout: communicationManager.timeoutDuration.toSeconds())
    XCTAssertEqual(delegate.error, .failedEncryptionEstablishment)
  }

  func testEncryptionSetupFails_notifiesDelegate() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: Data("Test".utf8),
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    // Secure channel establishment should now be set up.
    let reconnectionHandler =
      communicationManager.reconnectingHandlers.first(
        where: { $0.car.id == id.uuidString }
      ) as? ReconnectionHandlerFake

    XCTAssertNotNil(reconnectionHandler)

    communicationManager.reconnectionHandler(
      reconnectionHandler!,
      didEncounterError: .cannotEstablishEncryption
    )

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .failedEncryptionEstablishment)
    XCTAssert(delegate.peripheralWithError === car)
  }

  // MARK: - Happy path tests.

  func testValidCharacteristics_CallsEstablishEncryption() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    // Process the incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: Data("Test".utf8),
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    let reconnectionHelper = reconnectionHelpers[car.identifier]!
    XCTAssertTrue(reconnectionHelper.handleMessageCalled)

    // Secure channel should be created.
    XCTAssertEqual(reconnectionHandlerFactory.createdChannels.count, 1)

    // Secure channel establishment should now be set up.
    let reconnectionHandler =
      communicationManager.reconnectingHandlers.first(
        where: { $0.car.id == id.uuidString }
      ) as! ReconnectionHandlerFake

    XCTAssertTrue(reconnectionHandler.establishEncryptionCalled)
    XCTAssertEqual(reconnectionHandler.car, Car(id: id.uuidString, name: name))
    XCTAssert(reconnectionHandler.delegate === communicationManager)
  }

  func testHandshakeCompletes_CallsEstablishEncryption() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)
    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    let reconnectionHelper = reconnectionHelpers[car.identifier]!

    // First message should not complete the handshake.
    reconnectionHelper.shouldCompleteHandshake = false

    // Process the first incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: Data("Test".utf8),
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    // First message, handshake not complete -> No secure channel.
    XCTAssertTrue(reconnectionHelper.handleMessageCalled)
    XCTAssertEqual(reconnectionHandlerFactory.createdChannels.count, 0)

    // Next message should complete the handshake.
    reconnectionHelper.shouldCompleteHandshake = true

    // Process second incoming handshake message.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: Data("Test".utf8),
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    // Second message, handshake complete -> Secure channel should be created.
    XCTAssertEqual(reconnectionHandlerFactory.createdChannels.count, 1)

    // Secure channel establishment should now be set up.
    let reconnectionHandler =
      communicationManager.reconnectingHandlers.first(
        where: { $0.car.id == id.uuidString }
      ) as! ReconnectionHandlerFake

    XCTAssertTrue(reconnectionHandler.establishEncryptionCalled)
    XCTAssertEqual(reconnectionHandler.car, Car(id: id.uuidString, name: name))
    XCTAssert(reconnectionHandler.delegate === communicationManager)
  }

  func testEncryptionSetUp_NotifiesDelegateThatEncryptionBeingEstablished() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    // Send back the car's device id.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: id.data,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    let reconnectionHelper = reconnectionHelpers[car.identifier]!
    XCTAssertTrue(reconnectionHelper.handleMessageCalled)

    // Verify delegate that encryption being established.
    XCTAssertTrue(delegate.establishingSecureChannelCalled)
    XCTAssertEqual(delegate.establishingCar, Car(id: id.uuidString, name: name))
    XCTAssert(delegate.establishingPeripheral === car)
  }

  func testEncryptionSetUp_NotifiesDelegate() {
    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)

    let delegate = CommunicationManagerDelegateFake()
    communicationManager.delegate = delegate

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    establishSecureChannel(for: car, id: id)

    // Verify delegate notified.
    XCTAssertTrue(delegate.didEstablishSecureChannelCalled)
    XCTAssertNotNil(delegate.securedCarChannel)

    let expectedCar = Car(id: id.uuidString, name: name)
    XCTAssertEqual(delegate.securedCarChannel!.car, expectedCar)
  }

  func testEncryptionSetUp_doesNotTimeout() {
    communicationManager.timeoutDuration = DispatchTimeInterval.seconds(2)

    let id = makeRandomUUID()
    let name = "name"
    let car = PeripheralMock(name: name, services: [validService])

    setUpAssociatedCar(id: id.uuidString, car: car)

    let delegate = CommunicationManagerDelegateFake()
    communicationManager.delegate = delegate

    delegate.errorExpectation = expectation(description: "Delegate notified with error.")
    delegate.errorExpectation?.isInverted = true

    XCTAssertNoThrow(try communicationManager.setUpSecureChannel(with: car, id: nil))

    establishSecureChannel(for: car, id: id)

    waitForExpectations(timeout: communicationManager.timeoutDuration.toSeconds())
  }

  func testMessageCompressionAllowedFalseInOverlay() {
    communicationManager = CommunicationManager(
      overlay: Overlay([CommunicationManager.messageCompressionAllowedKey: false]),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannelFactory: self,
      bleVersionResolver: bleVersionResolver,
      reconnectionHandlerFactory: reconnectionHandlerFactory)

    XCTAssertFalse(communicationManager.isMessageCompressionAllowed)
  }

  func testMessageCompressionAllowedTrueInOverlay() {
    communicationManager = CommunicationManager(
      overlay: Overlay([CommunicationManager.messageCompressionAllowedKey: true]),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannelFactory: self,
      bleVersionResolver: bleVersionResolver,
      reconnectionHandlerFactory: reconnectionHandlerFactory)

    XCTAssertTrue(communicationManager.isMessageCompressionAllowed)
  }

  func testMessageCompressionDisabledMissingFromOverlay() {
    communicationManager = CommunicationManager(
      overlay: Overlay(["test": true]),
      connectionHandle: connectionHandle,
      uuidConfig: uuidConfig,
      associatedCarsManager: associatedCarsManagerMock,
      secureSessionManager: secureSessionManagerMock,
      secureBLEChannelFactory: self,
      bleVersionResolver: bleVersionResolver,
      reconnectionHandlerFactory: reconnectionHandlerFactory)

    XCTAssertTrue(communicationManager.isMessageCompressionAllowed)
  }

  func testDidUpdateAdvertisement_Matches_PreparesForHandshake() {
    let car = PeripheralMock(name: "name", services: [validService])
    setUpAssociatedCar(id: "id", car: car)

    let helper = reconnectionHelpers[car.identifier]
    XCTAssertNotNil(helper)

    guard let mockHelper = helper else { return }
    mockHelper.isReadyForHandshake = false
    mockHelper.prepareForHandshakeShouldSucceed = true

    communicationManager.peripheral(
      car,
      didUpdateValueFor: advertisementCharacteristicMock,
      error: nil
    )

    XCTAssertTrue(mockHelper.prepareForHandshakeCalled)
    XCTAssertTrue(mockHelper.isReadyForHandshake)
  }

  func testDidUpdateAdvertisement_NoMatch_PreparesForHandshakeFails() {
    let car = PeripheralMock(name: "name", services: [validService])
    setUpAssociatedCar(id: "id", car: car)

    let helper = reconnectionHelpers[car.identifier]
    XCTAssertNotNil(helper)

    guard let mockHelper = helper else { return }
    mockHelper.isReadyForHandshake = false
    mockHelper.prepareForHandshakeShouldSucceed = false

    communicationManager.peripheral(
      car,
      didUpdateValueFor: advertisementCharacteristicMock,
      error: nil
    )

    XCTAssertTrue(mockHelper.prepareForHandshakeCalled)
    XCTAssertFalse(mockHelper.isReadyForHandshake)
    XCTAssertTrue(delegate.didEncounterErrorCalled)
  }

  func testDidUpdateAdvertisement_MissingAdvertisement_Fails() {
    let car = PeripheralMock(name: "name", services: [validService])
    setUpAssociatedCar(id: "id", car: car)

    let helper = reconnectionHelpers[car.identifier]
    XCTAssertNotNil(helper)

    guard let mockHelper = helper else { return }
    mockHelper.isReadyForHandshake = false
    mockHelper.prepareForHandshakeShouldSucceed = true

    advertisementCharacteristicMock.value = nil
    communicationManager.peripheral(
      car,
      didUpdateValueFor: advertisementCharacteristicMock,
      error: nil
    )

    XCTAssertFalse(mockHelper.prepareForHandshakeCalled)
    XCTAssertFalse(mockHelper.isReadyForHandshake)
    XCTAssertTrue(delegate.didEncounterErrorCalled)
  }

  // MARK: - Helper functions.

  private func makeMockError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }

  private func setUpAssociatedCar(id: String, car: PeripheralMock) {
    // Ensure car is marked as associated.
    associatedCarsManagerMock.addAssociatedCar(identifier: id, name: car.name)

    // Ensure there is a valid secure session for the car. The value of the secure session is
    // arbitrary.
    secureSessionManagerMock.secureSessions[id] = SecureBLEChannelMock.mockSavedSession

    // Use a mock reconnection helper.
    let reconnectionHelper = ReconnectionHelperMock(peripheral: car, pendingCarId: id)
    reconnectionHelpers[car.identifier] = reconnectionHelper
    communicationManager.addReconnectionHelper(reconnectionHelper)
  }

  private func makeRandomUUID() -> CBUUID {
    return CBUUID(string: UUID().uuidString)
  }

  private func establishSecureChannel(for car: PeripheralMock, id: CBUUID) {
    communicationManager.peripheral(car, didDiscoverServices: nil)
    communicationManager.peripheral(
      car,
      didDiscoverCharacteristicsFor: validService,
      error: nil
    )
    communicationManager.bleVersionResolver(
      bleVersionResolver,
      didResolveStreamVersionTo: .passthrough,
      securityVersionTo: .v1,
      for: car
    )

    let pendingCar = communicationManager.pendingCars.first(where: { $0.car === car })!

    // Send back the car's device id.
    communicationManager.messageStream(
      pendingCar.messageStream!,
      didReceiveMessage: id.data,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    let reconnectionHelper = reconnectionHelpers[car.identifier]!
    XCTAssertTrue(reconnectionHelper.handleMessageCalled)

    XCTAssertEqual(reconnectionHandlerFactory.createdChannels.count, 1)
    let reconnectionHandler = reconnectionHandlerFactory.createdChannels[0]
    reconnectionHandler.notifyEncryptionEstablished()
  }
}

// MARK: - secureBLEChannelFactory

extension CommunicationManagerTest: SecureBLEChannelFactory {
  func makeChannel() -> SecureBLEChannel {
    return SecureBLEChannelMock()
  }
}
