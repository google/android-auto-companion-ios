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
@available(watchOS 6.0, *)
@MainActor class AssociationMessageHelperV1Test: XCTestCase {
  private var associatorMock: AssociatorMock!
  private var messageStreamMock: MessageStream!

  // The helper under test.
  private var messageHelper: AssociationMessageHelperV1!

  override func setUp() async throws {
    try await super.setUp()

    associatorMock = AssociatorMock()

    let peripheralMock = PeripheralMock(name: "Test")
    let readCharacteristic = CharacteristicMock(
      uuid: UUIDConfig.readCharacteristicUUID, value: nil)
    let writeCharacteristic = CharacteristicMock(
      uuid: UUIDConfig.writeCharacteristicUUID, value: nil)
    messageStreamMock = BLEMessageStreamPassthrough(
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic
    )

    messageHelper =
      AssociationMessageHelperV1(associatorMock, messageStream: messageStreamMock)
  }

  override func tearDown() {
    associatorMock = nil
    messageStreamMock = nil
    messageHelper = nil

    super.tearDown()
  }

  /// Test the good path for message handling.
  /// First message should be the carId.
  /// Second message should be the pairing code confirmation.
  func testHandleMessage_CarId_Encryption() {
    messageHelper.start()

    // Calling start should send the device id. Acknowledge that the message has been sent.
    messageHelper.messageDidSendSuccessfully()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    XCTAssertNotNil(associatorMock.carId)
    XCTAssertEqual(associatorMock.carId!, carId)
    XCTAssertNil(associatorMock.associationError)
    XCTAssertTrue(associatorMock.establishEncryptionCalled)

    let pairingMessage = Data(AssociationManager.pairingCodeConfirmationValue.utf8)
    messageHelper.handleMessage(pairingMessage, params: params)

    XCTAssertTrue(associatorMock.notifyPairingCodeAcceptedCalled)
  }

  /// Test receiving a bad pairing code confirmation.
  func testHandleMessage_BadPairing() {
    messageHelper.start()

    // Calling start should send the device id. Acknowledge that the message has been sent.
    messageHelper.messageDidSendSuccessfully()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    let pairingMessage = Data("bad".utf8)
    messageHelper.handleMessage(pairingMessage, params: params)

    XCTAssertFalse(associatorMock.notifyPairingCodeAcceptedCalled)
    XCTAssertTrue(associatorMock.notifyDelegateOfErrorCalled)
    XCTAssertNotNil(associatorMock.associationError)
    XCTAssertEqual(associatorMock.associationError, AssociationError.pairingCodeRejected)
  }

  /// Test receiving a good pairing code confirmation, but the associator rejected it.
  func testHandleMessage_AssociatorRejectedPairing() {
    associatorMock.shouldThrowWhenNotifyingPairingCodeAccepted = true
    messageHelper.start()

    // Calling start should send the device id. Acknowledge that the message has been sent.
    messageHelper.messageDidSendSuccessfully()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    let pairingMessage = Data(AssociationManager.pairingCodeConfirmationValue.utf8)
    messageHelper.handleMessage(pairingMessage, params: params)

    XCTAssertTrue(associatorMock.notifyPairingCodeAcceptedCalled)
    XCTAssertTrue(associatorMock.notifyDelegateOfErrorCalled)
    XCTAssertNotNil(associatorMock.associationError)
    XCTAssertEqual(associatorMock.associationError, AssociationError.pairingCodeRejected)
  }

  /// Test handling encryption established, but no carId.
  func testOnEncryptionEstablished_NoCarId() {
    associatorMock.carId = nil

    messageHelper.onEncryptionEstablished()

    XCTAssertNotNil(associatorMock.associationError)
    XCTAssertEqual(associatorMock.associationError, AssociationError.cannotStoreAssociation)
    XCTAssertFalse(associatorMock.completeAssociationCalled)
  }

  func testOnEncryptionEstablished_establishSecuredCarChannelFails() {
    associatorMock.establishSecuredCarChannelSucceeds = false

    messageHelper.onEncryptionEstablished()

    XCTAssertNotNil(associatorMock.associationError)
    XCTAssertEqual(associatorMock.associationError, AssociationError.cannotStoreAssociation)
    XCTAssertFalse(associatorMock.completeAssociationCalled)
  }
}
