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
import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager
@testable import AndroidAutoMessageStream

/// Unit tests for AssociationMessageHelperV1.
@MainActor class ReconnectionHelperV1Test: XCTestCase {
  private var messageStreamMock: MessageStream!
  private var peripheralMock: PeripheralMock!

  // The helper under test.
  private var testHelper: ReconnectionHelperV1!

  override func setUp() async throws {
    try await super.setUp()

    peripheralMock = PeripheralMock(name: "Test")

    let readCharacteristic = CharacteristicMock(
      uuid: UUIDConfig.readCharacteristicUUID, value: nil)
    let writeCharacteristic = CharacteristicMock(
      uuid: UUIDConfig.writeCharacteristicUUID, value: nil)
    messageStreamMock = BLEMessageStreamPassthrough(
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic
    )

    testHelper = ReconnectionHelperV1(peripheral: peripheralMock)
  }

  override func tearDown() {
    peripheralMock = nil
    messageStreamMock = nil
    testHelper = nil

    super.tearDown()
  }

  /// Test still ready for handshake after `prepareForHandshake()` called.
  func test_prepareForHandshake_stillReady() {
    XCTAssertTrue(testHelper.isReadyForHandshake)

    // Should already be ready, so the callback should not be called.
    var onReadyForHandshakeCalled = false
    testHelper.onReadyForHandshake = {
      onReadyForHandshakeCalled = true
    }

    testHelper.prepareForHandshake(withAdvertisementData: Data("advertisement".utf8))

    XCTAssertTrue(testHelper.isReadyForHandshake)
    XCTAssertFalse(onReadyForHandshakeCalled)

    // Appease code coverage so we don't get penalized for not calling the closure.
    testHelper.onReadyForHandshake?()
    XCTAssertTrue(onReadyForHandshakeCalled)
  }

  func testStartHandshake_SendsDeviceId() {
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 0)

    XCTAssertNoThrow(try testHelper.startHandshake(messageStream: messageStreamMock))

    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    XCTAssertEqual(peripheralMock.writtenData[0], DeviceIdManager.deviceId.data)
  }

  func testHandleMessageAuthenticatesMessage_CompletesHandshake() throws {
    try testHelper.startHandshake(messageStream: messageStreamMock)
    // The next message must be a valid 128 bit car Id.
    let completed = try testHelper.handleMessage(
      messageStream: messageStreamMock, message: Data("0123456789ABCDEF".utf8))
    XCTAssertTrue(completed)
  }

  func testDoesNotRequestSecuredChannelConfiguration() throws {
    let connectionHandler = ConnectionHandleFake()
    let channel = SecuredCarChannelMock(id: "test", name: "test")

    var completionCalled = false
    var configurationSuccess = false

    try testHelper.onResolvedSecurityVersion(.v1)
    testHelper.configureSecureChannel(channel, using: connectionHandler) { success in
      completionCalled = true
      configurationSuccess = success
    }

    XCTAssertTrue(completionCalled)
    XCTAssertTrue(configurationSuccess)
    XCTAssertFalse(connectionHandler.requestConfigurationCalled)
  }
}
