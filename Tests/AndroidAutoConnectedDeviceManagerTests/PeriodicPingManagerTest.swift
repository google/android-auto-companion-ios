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

import XCTest
@_implementationOnly import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager
@testable import AndroidAutoConnectedDeviceManagerMocks

@MainActor class PeriodicPingManagerTest: XCTestCase {
  private var manager: PeriodicPingManager!
  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private let testCarId = "testCarId"
  private let testCar = Car(id: "testCarId", name: "mock car")

  override func setUp() {
    super.setUp()

    connectedCarManagerMock = ConnectedCarManagerMock()
    manager = PeriodicPingManager(connectedCarManager: connectedCarManagerMock)
  }

  func testOnSecureChannelEstablished_saveConnectedCar() {
    manager.onSecureChannelEstablished(for: testCar)

    XCTAssertTrue(manager.connectedCar == testCar)
  }

  func testOnCarDisconnected_removeCar() {
    manager.onSecureChannelEstablished(for: testCar)

    manager.onCarDisconnected(testCar)

    XCTAssertNil(manager.connectedCar)
  }

  func testOnMessageReceived_pingMessage_sendBackAck() {
    let channel = SecuredCarChannelMock(car: testCar)

    manager.onSecureChannelEstablished(for: testCar)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    /// Receives ping from IHU.
    manager.onMessageReceived(makePingMessageData(), from: testCar)

    XCTAssertEqual(channel.writtenMessages.count, 1)
    checkMessageType(channel.writtenMessages[0], expectedType: PeriodicPingMessage.MessageType.ack)
  }

  func testOnMessageReceived_notPingMessage_ignore() {
    let channel = SecuredCarChannelMock(car: testCar)

    manager.onSecureChannelEstablished(for: testCar)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    /// Receives unknown message from IHU.
    manager.onMessageReceived(makeUnknownMessageData(), from: testCar)

    XCTAssertEqual(channel.writtenMessages.count, 0)
  }

  // MARK: - Private Methods

  private func makePingMessageData() -> Data {
    var message = PeriodicPingMessage()
    message.messageType = .ping
    return try! message.serializedData()
  }

  private func makeUnknownMessageData() -> Data {
    var message = PeriodicPingMessage()
    message.messageType = .unknown
    return try! message.serializedData()
  }

  private func checkMessageType(_ messageData: Data, expectedType: PeriodicPingMessage.MessageType)
  {
    let message = try! PeriodicPingMessage(serializedData: messageData)

    XCTAssertEqual(message.messageType, expectedType)
  }
}
