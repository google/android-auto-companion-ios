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
import AndroidAutoSecureChannel
import CoreBluetooth
import XCTest
import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager
@testable import AndroidAutoMessageStream

/// Unit tests for AssociationMessageHelperV2.
@available(iOS 10.0, watchOS 6.0, *)
class AssociationMessageHelperV2Test: XCTestCase {
  private typealias VerificationCodeState = Com_Google_Companionprotos_VerificationCodeState
  private typealias VerificationCode = Com_Google_Companionprotos_VerificationCode

  private var associatorMock: AssociatorMock!
  private var messageStreamMock: MessageStream!
  private var peripheralMock: PeripheralMock!

  // The helper under test.
  private var messageHelper: AssociationMessageHelperV2!

  override func setUp() {
    super.setUp()

    associatorMock = AssociatorMock()
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

    messageHelper = AssociationMessageHelperV2(
      associatorMock,
      messageStream: messageStreamMock
    )
  }

  override func tearDown() {
    associatorMock = nil
    peripheralMock = nil
    messageStreamMock = nil
    messageHelper = nil

    super.tearDown()
  }

  func testStart() {
    messageHelper.start()

    XCTAssertTrue(associatorMock.establishEncryptionCalled)
  }

  /// Test displaying pairing code and acceptance is assumed without IHU response.
  func testHandleMessage_DisplaysPairingCode() {
    messageHelper.start()

    messageHelper.onRequiresPairingVerification(FakeVerificationToken(pairingCode: "123456"))
    XCTAssertTrue(associatorMock.displayPairingCodeCalled)

    // No other messages should be sent during the handshake.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 0)

    messageHelper.onPairingCodeDisplayed()
    XCTAssertTrue(associatorMock.notifyPairingCodeAcceptedCalled)
  }

  /// Test the good path for message handling.
  /// First we initiate encryption and send the pairing code.
  /// After encryption is established the next message is the carId.
  /// We respond by sending the deviceId and authentication key.
  /// Then we complete the association.
  func testHandleMessage_Encryption_CarId() {
    messageHelper.start()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    messageHelper.onEncryptionEstablished()
    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    XCTAssertNotNil(associatorMock.carId)
    XCTAssertEqual(associatorMock.carId!, carId)
    XCTAssertNil(associatorMock.associationError)
    XCTAssertTrue(associatorMock.establishEncryptionCalled)
    XCTAssertNil(associatorMock.associationError)
    XCTAssertTrue(associatorMock.completeAssociationCalled)
  }
}

/// Fake verification token.
private struct FakeVerificationToken: SecurityVerificationToken {
  /// Full backing data.
  var data: Data { Data(pairingCode.utf8) }

  /// Human-readable visual pairing code.
  let pairingCode: String
}
