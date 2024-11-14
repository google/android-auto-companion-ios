// Copyright 2023 Google LLC
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

private import AndroidAutoConnectedDeviceManager
private import AndroidAutoConnectedDeviceManagerMocks
internal import XCTest

@testable private import AndroidAutoConnectionHowitzerManagerV2

class ConnectionHowitzerManagerV2Test: XCTestCase {
  private var manager: ConnectionHowitzerManagerV2!
  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private let testCarId1 = "testCarId1"
  private let testCarId2 = "testCarId2"
  private let testCar1 = Car(id: "testCarId1", name: "mock car 1")
  private let testCar2 = Car(id: "testCarId2", name: "mock car 2")

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    await setUpOnMain()
  }

  @MainActor private func setUpOnMain() {
    connectedCarManagerMock = ConnectedCarManagerMock()
    manager = ConnectionHowitzerManagerV2(connectedCarManager: connectedCarManagerMock)
  }

  @MainActor func testOnSecureChannelEstablished_noExistingConnectedCar_saveConnectedCar() {
    manager.onSecureChannelEstablished(for: testCar1)

    XCTAssertTrue(manager.connectedCar == testCar1)
  }

  @MainActor func testOnSecureChannelEstablished_existsConnectedCar_updateCar() {
    manager.onSecureChannelEstablished(for: testCar1)

    manager.onSecureChannelEstablished(for: testCar2)

    XCTAssertTrue(manager.connectedCar == testCar2)
  }

  @MainActor func testOnCarDisconnected_sameAsConnectedCar_removeCar() {
    manager.onSecureChannelEstablished(for: testCar1)

    manager.onCarDisconnected(testCar1)

    XCTAssertNil(manager.connectedCar)
  }

  @MainActor func testOnCarDisconnected_differentFromConnectedCar_doNothing() {
    manager.onSecureChannelEstablished(for: testCar1)

    manager.onCarDisconnected(testCar2)

    XCTAssertTrue(manager.connectedCar == testCar1)
  }

  @MainActor func testStart_sendConfigToIHU() {
    manager.onSecureChannelEstablished(for: testCar1)
    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    let config = HowitzerConfig(
      payloadSize: 100, payloadCount: 25, sentFromIHU: false)

    manager.start(with: config)
    let messageData = makeConfigMessageData(manager.testID!, manager.config)

    XCTAssertEqual(channel.writtenMessages.count, 1)
    XCTAssertEqual(channel.writtenMessages[0], messageData)
  }

  @MainActor func testStart_startTwice_failOnTheSecondTime() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    let channel = SecuredCarChannelMock(car: testCar1)
    manager.delegate = delegate
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    manager.start(with: manager.config)
    manager.start(with: manager.config)

    XCTAssertTrue(delegate.onTestFailed)
  }

  @MainActor func testStart_testDidNotFinish_canStartNewTestWhenReconnected() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    let channel = SecuredCarChannelMock(car: testCar1)
    manager.delegate = delegate
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    manager.start(with: manager.config)

    XCTAssertFalse(delegate.onTestCompletedSuccessfully)

    manager.onCarDisconnected(testCar1)
    connectedCarManagerMock.triggerDisconnection(for: testCar1)

    /// A new test should be able to start when reconnected.
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    manager.start(with: manager.config)

    XCTAssertFalse(delegate.onTestFailed)
  }

  @MainActor func testTestID_newTest_newTestID() {
    let channel = SecuredCarChannelMock(car: testCar1)
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    manager.start(with: manager.config)
    let testID1 = manager.testID!

    /// Test didn't finish before disconnection.
    manager.onCarDisconnected(testCar1)
    connectedCarManagerMock.triggerDisconnection(for: testCar1)
    /// Start a new test when reconnected.
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    manager.start(with: manager.config)
    let testID2 = manager.testID!

    XCTAssertFalse(testID1 == testID2)
  }

  @MainActor func testSendPayload_payloadSentMatchesConfig() {
    let config = HowitzerConfig(
      payloadSize: 100, payloadCount: 2, sentFromIHU: false)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    /// The first message is config and the rest payloads.
    let expectedMessageCount = Int(1 + config.payloadCount)

    XCTAssertEqual(channel.writtenMessages.count, expectedMessageCount)
    XCTAssertEqual(channel.writtenMessages.last!.count, Int(config.payloadSize))
  }

  @MainActor func testHandleResult_testIDMismatch_callOnTestFailed() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    manager.delegate = delegate
    let config = HowitzerConfig(
      payloadSize: 100, payloadCount: 2, sentFromIHU: false)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    // Construct IHU test result message.
    let ihuTestID = UUID()
    let message = makeValidResultMessageData(testID: ihuTestID, config: manager.config)
    manager.onMessageReceived(message, from: testCar1)

    XCTAssertTrue(delegate.onTestFailed)
  }

  @MainActor func testHandleResult_testInvalidResult_callOnTestFailed() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    manager.delegate = delegate
    let config = HowitzerConfig(
      payloadSize: 100, payloadCount: 2, sentFromIHU: false)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    // Construct IHU test result message.
    let message = makeInvalidResultMessageData(testID: manager.testID!, config: manager.config)
    manager.onMessageReceived(message, from: testCar1)

    XCTAssertTrue(delegate.onTestFailed)
  }

  @MainActor func testHandleResult_testValidResult_callOnTestCompletedSuccessfully() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    manager.delegate = delegate
    let config = HowitzerConfig(
      payloadSize: 100, payloadCount: 2, sentFromIHU: false)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    // Construct IHU test result message.
    let message = makeInvalidResultMessageData(testID: manager.testID!, config: manager.config)
    manager.onMessageReceived(message, from: testCar1)

    XCTAssertTrue(delegate.onTestFailed)
  }

  @MainActor func testReceivePayload_didNotReceiveAll_doNotSendResult() {
    let payloadSize = Int32(100)
    let payloadCount = Int32(5)
    let config = HowitzerConfig(
      payloadSize: payloadSize, payloadCount: payloadCount, sentFromIHU: true)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    receivePayloads(payloadCount - 1, testCar1)

    // 1st message is Config and no other messages should be sent.
    XCTAssertEqual(channel.writtenMessages.count, 1)
  }

  @MainActor func testReceivePayload_receivedAll_sendResult() {
    let payloadSize = Int32(100)
    let payloadCount = Int32(5)
    let config = HowitzerConfig(
      payloadSize: payloadSize, payloadCount: payloadCount, sentFromIHU: true)
    let channel = SecuredCarChannelMock(car: testCar1)
    finishConfigAck(with: channel, with: config)

    receivePayloads(payloadCount, testCar1)

    // 1st message: Config; 2nd message: Result.
    XCTAssertEqual(channel.writtenMessages.count, 2)
  }

  @MainActor func testResultAck_receivedDifferentType_callOnTestFailed() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    let payloadSize = Int32(100)
    let payloadCount = Int32(5)
    let config = HowitzerConfig(
      payloadSize: payloadSize, payloadCount: payloadCount, sentFromIHU: true)
    let channel = SecuredCarChannelMock(car: testCar1)
    manager.delegate = delegate
    finishConfigAck(with: channel, with: config)
    receivePayloads(payloadCount, testCar1)

    manager.onMessageReceived(makePayloadMessageData(payloadSize), from: testCar1)

    XCTAssertTrue(delegate.onTestFailed)
  }

  @MainActor func testResultAck_receivedAck_callOnTestCompletedSuccessfully() {
    let delegate = ConnectionHowitzerManagerV2DelegateMock()
    let payloadSize = Int32(100)
    let payloadCount = Int32(5)
    let config = HowitzerConfig(
      payloadSize: payloadSize, payloadCount: payloadCount, sentFromIHU: true)
    let channel = SecuredCarChannelMock(car: testCar1)
    manager.delegate = delegate
    finishConfigAck(with: channel, with: config)
    receivePayloads(payloadCount, testCar1)

    manager.onMessageReceived(makeAckMessageData(), from: testCar1)

    XCTAssertTrue(delegate.onTestCompletedSuccessfully)
  }

  @MainActor private func finishConfigAck(
    with channel: SecuredCarChannelMock,
    with config: HowitzerConfig
  ) {
    manager.onSecureChannelEstablished(for: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    manager.start(with: config)
    /// Receives config ack from IHU.
    manager.onMessageReceived(makeAckMessageData(), from: testCar1)
  }

  @MainActor private func receivePayloads(_ count: Int32, _ car: Car) {
    for _ in 1...count {
      manager.onMessageReceived(makePayloadMessageData(manager.config.payloadSize), from: car)
    }
  }

  private func makeConfigMessageData(_ testID: UUID, _ config: HowitzerConfig) -> Data {
    let message = HowitzerMessage(testID: testID, config: config)
    return try! message.serializedData()
  }

  private func makeAckMessageData() -> Data {
    let message = HowitzerMessage(type: HowitzerMessageProto.MessageType.ack)
    return try! message.serializedData()
  }

  private func makePayloadMessageData(_ size: Int32) -> Data {
    return Data((0..<size).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
  }

  private func makeInvalidResultMessageData(testID: UUID, config: HowitzerConfig) -> Data {
    let result = HowitzerResult(
      isValid: false,
      payloadReceivedTimestamps: [],
      testStartTime: TimeInterval()
    )
    let message = HowitzerMessage(testID: testID, config: config, result: result)

    return try! message.serializedData()
  }

  private func makeValidResultMessageData(testID: UUID, config: HowitzerConfig) -> Data {
    let testStartTime = Date().timeIntervalSince1970
    let payloadReceivedTimestamps = [
      TimeInterval(testStartTime + 0.1), TimeInterval(testStartTime + 0.2),
    ]
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: payloadReceivedTimestamps,
      testStartTime: testStartTime
    )
    let message = HowitzerMessage(testID: testID, config: config, result: result)

    return try! message.serializedData()
  }
}
