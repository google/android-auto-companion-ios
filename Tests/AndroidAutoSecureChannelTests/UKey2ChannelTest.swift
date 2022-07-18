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

import AndroidAutoConnectedDeviceTransportFakes
import AndroidAutoMessageStream
import AndroidAutoUKey2Wrapper
import CoreBluetooth
import XCTest

@testable import AndroidAutoSecureChannel

/// Unit tests for `UKey2Channel`.
class UKey2ChannelTest: XCTestCase {
  private static let recipientUUID = UUID(uuidString: "9f024256-06aa-423d-be60-93b086adce12")!

  private var messageStream: FakeMessageStream!
  private var ukey2Channel: UKey2Channel!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    messageStream = FakeMessageStream(peripheral: FakePeripheral())
    ukey2Channel = UKey2Channel()
  }

  // MARK: - establish(with:readCharacteristic:) tests.

  func testEstablish_setsDelegateOnPeripheral() {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))
    XCTAssertNotNil(ukey2Channel.messageStream)
    XCTAssert(ukey2Channel.messageStream!.delegate === ukey2Channel)
  }

  func testEstablish_setsStateToInProgress() {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))
    XCTAssertEqual(ukey2Channel.state, .inProgress)
  }

  func testEstablish_sendsCorrectInitMessage() {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))
    XCTAssertEqual(messageStream.writtenData.count, 1)

    let car = UKey2Wrapper(role: .responder)

    // Check that the car is able to decode the message generated from establish().
    let phoneMessage = messageStream.writtenData[0]
    let result = car.parseHandshakeMessage(phoneMessage)

    XCTAssertTrue(result.isSuccessful)
  }

  func testEstablish_notifiesDelegateOfError() {
    messageStream.writeMessageSucceeds = { false }
    XCTAssertThrowsError(try ukey2Channel.establish(using: messageStream))
  }

  // MARK: - Continue handshake tests.

  func testHandshakeFlow_leadsToVerificationNeeded() {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(messageStream.writtenData.count, 1)

    let car = UKey2Wrapper(role: .responder)

    var phoneMessage = messageStream.writtenData[0]
    var result = car.parseHandshakeMessage(phoneMessage)
    XCTAssertTrue(result.isSuccessful)

    let carMessage = car.nextHandshakeMessage()!

    simulateMessageFromCar(carMessage)

    // phone should send message to car to let it know it has received its message.
    XCTAssertEqual(messageStream.writtenData.count, 2)

    phoneMessage = messageStream.writtenData[1]
    result = car.parseHandshakeMessage(phoneMessage)
    XCTAssertTrue(result.isSuccessful)
    XCTAssertEqual(car.handshakeState, .verificationNeeded)

    // The UKey2Channel should also be in verification state.
    XCTAssertEqual(ukey2Channel.state, .verificationNeeded)
  }

  func testHandshakeFlow_errorNotifiesDelegate() {
    let delegateMock = SecureBLEChannelDelegateMock()
    ukey2Channel.delegate = delegateMock

    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(messageStream.writtenData.count, 1)

    let car = UKey2Wrapper(role: .responder)

    let phoneMessage = messageStream.writtenData[0]
    let result = car.parseHandshakeMessage(phoneMessage)
    XCTAssertTrue(result.isSuccessful)

    let carMessage = car.nextHandshakeMessage()!

    // Simulate error writing the next handshake message.
    messageStream.writeMessageSucceeds = { false }
    simulateMessageFromCar(carMessage)

    XCTAssertTrue(delegateMock.encounteredErrorCalled)
  }

  // MARK: - Verification code tests.

  func testHandshakeFlow_notifiesDelegateThatVerificationIsNeeded() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(messageStream.writtenData.count, 1)

    let car = UKey2Wrapper(role: .responder)

    let phoneMessage = messageStream.writtenData[0]
    car.parseHandshakeMessage(phoneMessage)

    let carMessage = car.nextHandshakeMessage()!
    simulateMessageFromCar(carMessage)

    XCTAssertTrue(delegateMock.requiresVerificationCalled)
  }

  func testHandshakeFlow_pairingCodePasssedToDelegateMatchesCar() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(messageStream.writtenData.count, 1)

    let car = UKey2Wrapper(role: .responder)

    var phoneMessage = messageStream.writtenData[0]
    car.parseHandshakeMessage(phoneMessage)

    let carMessage = car.nextHandshakeMessage()!
    simulateMessageFromCar(carMessage)

    // phone should send message to car to let it know it has received its message.
    XCTAssertEqual(messageStream.writtenData.count, 2)

    phoneMessage = messageStream.writtenData[1]
    car.parseHandshakeMessage(phoneMessage)
    let verificationBytes = car.verificationData(withByteLength: 32)
    let token = UKey2Channel.VerificationToken(verificationBytes!)
    let pairingCodeStr = token.pairingCode

    XCTAssertEqual(delegateMock.requiredVerificationData, verificationBytes)
    XCTAssertEqual(delegateMock.requiredPairingCode, pairingCodeStr)
  }

  func testVerificationTokenReadablePairingCode_modsBytesAcrossRange() {
    // 194 is an example of a value that would fail if using signed instead of unsigned ints
    // 194 -> 11000010
    // 11000010 -> 194 (unsigned 8-bit int)
    // 11000010 -> -62 (signed 8-bit int)
    let bytes = Data.init(bytes: [0, 7, 161, 194, 196, 255] as [UInt8], count: 6)
    let token = UKey2Channel.VerificationToken(bytes)

    XCTAssertEqual(token.pairingCode, "071465")
  }

  // MARK: - Notify pairing code called tests.

  func testNotifyPairingCodeAccepted_completesEstablishment() {
    setUpHandshake(phoneChannel: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    XCTAssertEqual(ukey2Channel.state, .established)
  }

  func testNotifyPairingCodeAccepted_notifiesDelegateOfEstablishment() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    setUpHandshake(phoneChannel: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    XCTAssertTrue(delegateMock.secureChannelEstablishedCalled)
    XCTAssert(delegateMock.establishedStream === messageStream)
  }

  func testNotifyPairingCodeAccepted_setMessageEncryptor() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    setUpHandshake(phoneChannel: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    // UKey2Channel should set itself as the message encryptor.
    XCTAssertNotNil(messageStream.messageEncryptor)
    XCTAssert(messageStream.messageEncryptor as! UKey2Channel === ukey2Channel)
  }

  // MARK: - Encrypt/Decrypt messages tests.

  func testEncrypt_carCanDecryptMessages() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    let car = setUpHandshake(phoneChannel: ukey2Channel)

    // Verify to complete the secure channel setup.
    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())
    car.verifyHandshake()

    let message = Data("Hello World".utf8)
    let encryptedMessage = try? ukey2Channel.encrypt(message)

    XCTAssertNotNil(encryptedMessage)
    XCTAssertEqual(car.decode(encryptedMessage!), message)
  }

  func testDecrypt_phoneCanDecryptCarMessage() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    let car = setUpHandshake(phoneChannel: ukey2Channel)

    // Verify to complete the secure channel setup.
    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())
    car.verifyHandshake()

    let message = Data("Hello World".utf8)
    let encryptedMessage = car.encode(message)!

    XCTAssertEqual(try? ukey2Channel.decrypt(encryptedMessage), message)
  }

  // MARK - Operation type check tests.

  func testOperationType_respectedForV2Stream() {
    let delegate = SecureBLEChannelDelegateMock()
    ukey2Channel.delegate = delegate

    let v2Stream = FakeMessageStream(peripheral: FakePeripheral(), version: .v2(true))

    XCTAssertNoThrow(try ukey2Channel.establish(using: v2Stream))

    let carMessage = Data("message".utf8)

    // Sending message back with wrong operation type.
    simulateMessageFromCar(carMessage, operationType: .clientMessage)

    // Delegate should be notified of error.
    XCTAssertTrue(delegate.encounteredErrorCalled)
    XCTAssertNotNil(delegate.encounteredError)

    // Note: using `case` for comparison because parseMessageFailed has an associated value. Cannot
    // use direct comparison with `==`.
    if case .parseMessageFailed = delegate.encounteredError as? SecureBLEChannelError {
    } else {
      XCTFail("Encountered error \(delegate.encounteredError!) is not equal to .parseMessageFailed")
    }
  }

  // MARK: - Reconnection flow tests

  func testReconnection() {
    var car = setUpHandshake(phoneChannel: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    car.verifyHandshake()

    // Runs through the reconnection flow as outlined by go/d2dsessionresumption.
    for _ in 1...1000 {
      let carSession = car.saveSession()!
      let phoneSession = try! ukey2Channel.saveSession()

      // Reset messages to make for easier verification
      messageStream.writtenData = []

      car = UKey2Wrapper(savedSession: carSession)!
      let carKey = car.uniqueSessionKey!

      XCTAssertNoThrow(
        try ukey2Channel.establish(using: messageStream, withSavedSession: phoneSession))

      XCTAssertEqual(ukey2Channel.state, .inProgress)

      car = UKey2Wrapper(role: .responder)
      var phoneMessage = messageStream.writtenData[0]
      car.parseHandshakeMessage(phoneMessage)

      let carMessage = car.nextHandshakeMessage()!

      simulateMessageFromCar(carMessage)

      phoneMessage = messageStream.writtenData[1]
      car.parseHandshakeMessage(phoneMessage)

      car.verificationData(withByteLength: 32)
      car.verifyHandshake()

      XCTAssertEqual(ukey2Channel.state, .resumingSession)

      ukey2Channel.messageStreamDidWriteMessage(
        ukey2Channel.messageStream!, to: Self.recipientUUID)

      var combinedSessionKey = Data()
      combinedSessionKey.append(carKey)
      combinedSessionKey.append(car.uniqueSessionKey!)

      let resumptionSalt = Data("RESUME".utf8)
      let phoneInfoPrefix = Data("CLIENT".utf8)

      let resumeHMAC = CryptoOps.hkdf(
        inputKeyMaterial: combinedSessionKey,
        salt: resumptionSalt,
        info: phoneInfoPrefix
      )

      phoneMessage = messageStream.writtenData[2]
      XCTAssertEqual(phoneMessage, resumeHMAC)

      let carInfoPrefix = Data("SERVER".utf8)
      let carHMAC = CryptoOps.hkdf(
        inputKeyMaterial: combinedSessionKey,
        salt: resumptionSalt,
        info: carInfoPrefix
      )!

      simulateMessageFromCar(carHMAC)

      XCTAssertEqual(ukey2Channel.state, .established)
    }
  }

  func testReconnectionError_notifiesDelegate() {
    let delegateMock = SecureBLEChannelDelegateMock()
    ukey2Channel.delegate = delegateMock

    var car = setUpHandshake(phoneChannel: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    car.verifyHandshake()

    let carSession = car.saveSession()!
    let phoneSession = try! ukey2Channel.saveSession()

    // Reset messages to make for easier verification
    messageStream.writtenData = []

    car = UKey2Wrapper(savedSession: carSession)!

    XCTAssertNoThrow(
      try ukey2Channel.establish(using: messageStream, withSavedSession: phoneSession))

    XCTAssertEqual(ukey2Channel.state, .inProgress)

    car = UKey2Wrapper(role: .responder)
    let phoneMessage = messageStream.writtenData[0]
    car.parseHandshakeMessage(phoneMessage)

    let carMessage = car.nextHandshakeMessage()!

    // Simulate an error writing the resumption message. There are two messages that will be sent
    // consecutively by the phone after it receives a message from the car.
    messageStream.writeMessageSucceeds = {
      self.ukey2Channel.state != .resumingSession
    }
    simulateMessageFromCar(carMessage)

    XCTAssertTrue(delegateMock.encounteredErrorCalled)
  }

  // MARK: - Helper functions.

  /// Simulates to the `UKey2Channel` that the given `message` has been sent from the car.
  private func simulateMessageFromCar(
    _ message: Data,
    operationType: StreamOperationType = .encryptionHandshake
  ) {
    ukey2Channel.messageStream(
      ukey2Channel.messageStream!,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: Self.recipientUUID,
        operationType: operationType
      )
    )
  }

  /// Runs through the encryption flow and ensures a secure channel is set up between the given
  /// phone and a car.
  ///
  /// - Parameter phoneChannel: The `UKey2Channel` that handles secure connection and
  ///     represents the phone.
  /// - Returns: The car instance, which just needs verification of its pairing code.
  @discardableResult
  private func setUpHandshake(phoneChannel: UKey2Channel) -> UKey2Wrapper {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    let car = UKey2Wrapper(role: .responder)

    var phoneMessage = messageStream.writtenData[0]
    car.parseHandshakeMessage(phoneMessage)

    let carMessage = car.nextHandshakeMessage()!
    simulateMessageFromCar(carMessage)

    phoneMessage = messageStream.writtenData[1]
    car.parseHandshakeMessage(phoneMessage)

    // Ensure car is in verification mode.
    car.verificationData(withByteLength: 32)

    return car
  }
}

// MARK: - Mocks.

/// A mock of `SecureBLEChannelDelegate` that allows for verification that its callback methods
/// have been called.
class SecureBLEChannelDelegateMock: SecureBLEChannelDelegate {
  var requiresVerificationCalled = false
  var requiredVerificationData: Data?
  var requiredPairingCode: String?
  var verificationStream: MessageStream?

  var secureChannelEstablishedCalled = false
  var establishedStream: MessageStream?

  var encounteredErrorCalled = false
  var encounteredError: Error?

  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    requiresVerificationOf verificationToken: SecurityVerificationToken,
    messageStream: MessageStream
  ) {
    requiresVerificationCalled = true
    requiredVerificationData = verificationToken.data
    requiredPairingCode = verificationToken.pairingCode
    verificationStream = messageStream
  }

  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    establishedUsing messageStream: MessageStream
  ) {
    secureChannelEstablishedCalled = true
    establishedStream = messageStream
  }

  func secureBLEChannel(_ secureBLEChannel: SecureBLEChannel, encounteredError error: Error) {
    encounteredErrorCalled = true
    encounteredError = error
  }
}
