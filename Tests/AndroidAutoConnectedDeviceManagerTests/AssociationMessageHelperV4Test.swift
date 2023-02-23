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
@_implementationOnly import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager
@testable import AndroidAutoMessageStream

/// Unit tests for AssociationMessageHelperV4.
@available(watchOS 6.0, *)
@MainActor class AssociationMessageHelperV4Test: XCTestCase {
  private typealias VerificationCodeState = Com_Google_Companionprotos_VerificationCodeState
  private typealias VerificationCode = Com_Google_Companionprotos_VerificationCode

  private var associatorMock: AssociatorMock!
  private var messageStreamMock: MessageStream!
  private var peripheralMock: PeripheralMock!

  // The helper under test.
  private var messageHelper: AssociationMessageHelperV4!

  override func setUp() async throws {
    try await super.setUp()

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

    messageHelper = AssociationMessageHelperV4(associatorMock, messageStream: messageStreamMock)
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

  /// Test displaying pairing code while sending the verification code.
  func testHandleMessage_DisplaysPairingCode() throws {
    messageHelper.start()

    messageHelper.onRequiresPairingVerification(FakeVerificationToken(pairingCode: "123456"))
    XCTAssertTrue(associatorMock.displayPairingCodeCalled)

    // Visual verification code sent.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    let lastMessage = peripheralMock.writtenData.last!
    let code = try VerificationCode(serializedData: lastMessage)
    XCTAssertEqual(code.state, .visualVerification)
    messageHelper.onPairingCodeDisplayed()

    // The IHU sends back confirmation of the verification code.
    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )
    var confirmation = VerificationCode()
    confirmation.state = .visualConfirmation
    let confirmationMessage = try confirmation.serializedData()
    messageHelper.handleMessage(confirmationMessage, params: params)

    XCTAssertTrue(associatorMock.notifyPairingCodeAcceptedCalled)
    XCTAssertFalse(associatorMock.notifyDelegateOfErrorCalled)
  }

  /// Test that the pairing code is not accepted if the IHU doesn't confirm.
  func testNoConfirmation_PairingCodeNotAccepted() throws {
    messageHelper.start()

    messageHelper.onRequiresPairingVerification(FakeVerificationToken(pairingCode: "123456"))
    XCTAssertTrue(associatorMock.displayPairingCodeCalled)

    // Verification is sent since this is for Security V4.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    let lastMessage = peripheralMock.writtenData.last!
    let code = try VerificationCode(serializedData: lastMessage)
    XCTAssertEqual(code.state, .visualVerification)
    messageHelper.onPairingCodeDisplayed()

    // The IHU doesn't send back the expected confirmation of the verification code.
    XCTAssertFalse(associatorMock.notifyPairingCodeAcceptedCalled)
  }

  /// Test out-of-band verification without displaying pairing code.
  func testHandleMessage_OutOfBandVerification() throws {
    messageHelper.start()

    let mockOutOfBandToken = MockOutOfBandToken()
    associatorMock.outOfBandToken = mockOutOfBandToken
    let verificationToken = FakeVerificationToken(pairingCode: "123456")
    messageHelper.onRequiresPairingVerification(verificationToken)

    XCTAssertTrue(mockOutOfBandToken.encryptCalled)
    // Out of band association, so pairing code shouldn't be displayed.
    XCTAssertFalse(associatorMock.displayPairingCodeCalled)

    // OOB Verification code sent.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    let lastMessage = peripheralMock.writtenData.last!
    let code = try VerificationCode(serializedData: lastMessage)
    XCTAssertEqual(code.state, .oobVerification)

    // The IHU sends back confirmation of the verification code.
    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )
    let ihuOutOfBandToken = MockOutOfBandToken()
    var confirmationCode = VerificationCode()
    confirmationCode.state = .oobVerification
    confirmationCode.payload = try ihuOutOfBandToken.encrypt(verificationToken.data)
    let confirmationMessage = try confirmationCode.serializedData()
    messageHelper.handleMessage(confirmationMessage, params: params)

    XCTAssertTrue(mockOutOfBandToken.decryptCalled)
    XCTAssertTrue(associatorMock.notifyPairingCodeAcceptedCalled)
    XCTAssertFalse(associatorMock.notifyDelegateOfErrorCalled)
  }

  /// Test out-of-band verification mismatch -> pairing fails.
  func testHandleMessage_OutOfBandVerificationMismatch_PairingFails() throws {
    messageHelper.start()

    let mockOutOfBandToken = MockOutOfBandToken()
    associatorMock.outOfBandToken = mockOutOfBandToken
    let verificationToken = FakeVerificationToken(pairingCode: "123456")
    messageHelper.onRequiresPairingVerification(verificationToken)

    // OOB Verification code sent.
    let lastMessage = peripheralMock.writtenData.last!
    let code = try VerificationCode(serializedData: lastMessage)
    XCTAssertEqual(code.state, .oobVerification)

    // The IHU sends back confirmation of the verification code.
    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )
    var confirmationCode = VerificationCode()
    confirmationCode.state = .oobVerification
    // Send data other than the encrypted verification code.
    confirmationCode.payload = Data()
    let confirmationMessage = try confirmationCode.serializedData()
    messageHelper.handleMessage(confirmationMessage, params: params)

    XCTAssertFalse(associatorMock.notifyPairingCodeAcceptedCalled)
    XCTAssertTrue(associatorMock.notifyDelegateOfErrorCalled)
  }

  // MARK: - messageDidSendSuccessfully tests

  func testMessageDidSendSuccessfully_noCarId_notifiesDelegate() {
    messageHelper.start()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    messageHelper.onEncryptionEstablished()
    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    associatorMock.carId = nil

    // This should trigger the sending of the deviceId and authentication key. Acknowledge that
    // this completes successfully
    messageHelper.messageDidSendSuccessfully()

    XCTAssertTrue(associatorMock.notifyDelegateOfErrorCalled)
    XCTAssertEqual(associatorMock.associationError, .cannotStoreAssociation)
  }

  func testMessageDidSendSuccessfully_establishSecuredCarChannelFailed_notifiesDelegate() {
    associatorMock.establishSecuredCarChannelSucceeds = false

    messageHelper.start()

    let params = MessageStreamParams(
      recipient: UUID(),
      operationType: .encryptionHandshake
    )

    messageHelper.onEncryptionEstablished()
    let carId = UUID().uuidString
    let carIdMessage = CBUUID(string: carId).data
    messageHelper.handleMessage(carIdMessage, params: params)

    // This should trigger the sending of the deviceId and authentication key. Acknowledge that
    // this completes successfully
    messageHelper.messageDidSendSuccessfully()

    XCTAssertTrue(associatorMock.notifyDelegateOfErrorCalled)
    XCTAssertEqual(associatorMock.associationError, .cannotStoreAssociation)
  }

  func testMessageDidSendSuccessfully_ignoredIfWrongState() {
    messageHelper.start()
    messageHelper.messageDidSendSuccessfully()

    // No errors or completion should be present.
    XCTAssertFalse(associatorMock.notifyDelegateOfErrorCalled)
    XCTAssertFalse(associatorMock.establishSecuredCarChannelCalled)
    XCTAssertFalse(associatorMock.completeAssociationCalled)
  }

  // MARK: - Happy path test

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

    // This should trigger the sending of the deviceId and authentication key. Acknowledge that
    // this completes successfully
    messageHelper.messageDidSendSuccessfully()

    XCTAssertNotNil(associatorMock.carId)
    XCTAssertEqual(associatorMock.carId!, carId)
    XCTAssertNil(associatorMock.associationError)
    XCTAssertTrue(associatorMock.establishEncryptionCalled)
    XCTAssertNil(associatorMock.associationError)
    XCTAssertTrue(associatorMock.establishSecuredCarChannelCalled)
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

/// Mock out of band token.
private class MockOutOfBandToken: OutOfBandToken {
  var encryptCalled = false
  var decryptCalled = false

  /// Encrypt the message by reversing it.
  func encrypt(_ message: Data) throws -> Data {
    encryptCalled = true
    return Data(message.reversed())
  }

  /// Decrypt the message by reversing it.
  func decrypt(_ message: Data) throws -> Data {
    decryptCalled = true
    return Data(message.reversed())
  }
}
