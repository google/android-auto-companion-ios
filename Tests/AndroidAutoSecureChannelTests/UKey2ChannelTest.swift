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

import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import AndroidAutoMessageStream
import AndroidAutoUKey2Wrapper
import CoreBluetooth
import XCTest

@testable import AndroidAutoSecureChannel

/// Unit tests for `UKey2Channel`.
@available(iOS 10.0, *)
class UKey2ChannelTest: XCTestCase {
  private static let recipientUUID = UUID(uuidString: "9f024256-06aa-423d-be60-93b086adce12")!

  private let peripheralMock = PeripheralMock(name: "name")
  private let readCharacteristicMock = CharacteristicMock(uuid: CBUUID(string: "bad1"), value: nil)
  private let writeCharacteristicMock = CharacteristicMock(uuid: CBUUID(string: "bad2"), value: nil)
  private var messageStream: MessageStream!

  private var ukey2Channel: UKey2Channel!

  override func setUp() {
    super.setUp()

    messageStream = BLEMessageStreamFactory.makeStream(
      version: .passthrough,
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristicMock,
      writeCharacteristic: writeCharacteristicMock,
      allowsCompression: true
    )

    continueAfterFailure = false
    peripheralMock.reset()
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
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    let server = UKey2Wrapper(role: .responder)

    // Check that the server is able to decode the message generated from establish().
    let clientMessage = peripheralMock.writtenData[0]
    let result = server.parseHandshakeMessage(clientMessage)

    XCTAssertTrue(result.isSuccessful)
  }

  // MARK: - Continue handshake tests.

  func testHandshakeFlow_leadsToVerificationNeeded() {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    let server = UKey2Wrapper(role: .responder)

    var clientMessage = peripheralMock.writtenData[0]
    var result = server.parseHandshakeMessage(clientMessage)
    XCTAssertTrue(result.isSuccessful)

    let serverMesssage = server.nextHandshakeMessage()!

    // Send server message back down to client via the callback.
    readCharacteristicMock.value = serverMesssage
    simulateMessageFromServer(serverMesssage)

    // Client should send message to server to let it know it has received its message.
    XCTAssertEqual(peripheralMock.writtenData.count, 2)

    clientMessage = peripheralMock.writtenData[1]
    result = server.parseHandshakeMessage(clientMessage)
    XCTAssertTrue(result.isSuccessful)
    XCTAssertEqual(server.handshakeState, .verificationNeeded)

    // The UKey2Channel should also be in verification state.
    XCTAssertEqual(ukey2Channel.state, .verificationNeeded)
  }

  // MARK: - Verification code tests.

  func testHandshakeFlow_notifiesDelegateThatVerificationIsNeeded() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    let server = UKey2Wrapper(role: .responder)

    let clientMessage = peripheralMock.writtenData[0]
    server.parseHandshakeMessage(clientMessage)

    let serverMesssage = server.nextHandshakeMessage()!

    // Send server message back down to client via the callback.
    readCharacteristicMock.value = serverMesssage
    ukey2Channel.messageStream(
      ukey2Channel.messageStream!,
      didReceiveMessage: serverMesssage,
      params: MessageStreamParams(
        recipient: Self.recipientUUID,
        operationType: .encryptionHandshake
      )
    )

    XCTAssertTrue(delegateMock.requiresVerificationCalled)
  }

  func testHandshakeFlow_pairingCodePasssedToDelegateMatchesServer() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    let server = UKey2Wrapper(role: .responder)

    var clientMessage = peripheralMock.writtenData[0]
    server.parseHandshakeMessage(clientMessage)

    let serverMesssage = server.nextHandshakeMessage()!

    // Send server message back down to client via the callback.
    readCharacteristicMock.value = serverMesssage
    simulateMessageFromServer(serverMesssage)

    // Client should send message to server to let it know it has received its message.
    XCTAssertEqual(peripheralMock.writtenData.count, 2)

    clientMessage = peripheralMock.writtenData[1]
    server.parseHandshakeMessage(clientMessage)
    let verificationBytes = server.verificationData(withByteLength: 32)
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
    setUpHandshake(client: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    XCTAssertEqual(ukey2Channel.state, .established)
  }

  func testNotifyPairingCodeAccepted_notifiesDelegateOfEstablishment() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    setUpHandshake(client: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    XCTAssertTrue(delegateMock.secureChannelEstablishedCalled)
    XCTAssert(delegateMock.establishedStream === messageStream)
  }

  func testNotifyPairingCodeAccepted_setMessageEncryptor() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    setUpHandshake(client: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    // UKey2Channel should set itself as the message encryptor.
    XCTAssertNotNil(messageStream.messageEncryptor)
    XCTAssert(messageStream.messageEncryptor as! UKey2Channel === ukey2Channel)
  }

  // MARK: - Encrypt/Decrypt messages tests.

  func testEncrypt_serverCanDecryptMessages() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    let server = setUpHandshake(client: ukey2Channel)

    // Verify to complete the secure channel setup.
    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())
    server.verifyHandshake()

    let message = Data("Hello World".utf8)
    let encryptedMessage = try? ukey2Channel.encrypt(message)

    XCTAssertNotNil(encryptedMessage)
    XCTAssertEqual(server.decode(encryptedMessage!), message)
  }

  func testDecrypt_clientCanDecryptServerMessage() {
    let delegateMock = SecureBLEChannelDelegateMock()

    ukey2Channel.delegate = delegateMock

    let server = setUpHandshake(client: ukey2Channel)

    // Verify to complete the secure channel setup.
    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())
    server.verifyHandshake()

    let message = Data("Hello World".utf8)
    let encryptedMessage = server.encode(message)!

    XCTAssertEqual(try? ukey2Channel.decrypt(encryptedMessage), message)
  }

  // MARK - Operation type check tests.

  func testOperationType_respectedForV2Stream() {
    let delegate = SecureBLEChannelDelegateMock()
    ukey2Channel.delegate = delegate

    let v2Stream = BLEMessageStreamFactory.makeStream(
      version: .v2(true),
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristicMock,
      writeCharacteristic: writeCharacteristicMock,
      allowsCompression: true
    )

    XCTAssertNoThrow(try ukey2Channel.establish(using: v2Stream))

    let serverMesssage = Data("message".utf8)

    // Sending message back with wrong operation type.
    ukey2Channel.messageStream(
      v2Stream,
      didReceiveMessage: serverMesssage,
      params: MessageStreamParams(
        recipient: Self.recipientUUID,
        operationType: .clientMessage
      )
    )

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
    var server = setUpHandshake(client: ukey2Channel)

    XCTAssertNoThrow(try ukey2Channel.notifyPairingCodeAccepted())

    server.verifyHandshake()

    // Runs through the reconnection flow as outlined by go/d2dsessionresumption.
    for _ in 1...1000 {
      let serverSession = server.saveSession()!
      let clientSession = try! ukey2Channel.saveSession()

      // Reset messages to make for easier verification
      peripheralMock.writtenData = []

      server = UKey2Wrapper(savedSession: serverSession)!
      let serverKey = server.uniqueSessionKey!

      XCTAssertNoThrow(
        try ukey2Channel.establish(using: messageStream, withSavedSession: clientSession))

      XCTAssertEqual(ukey2Channel.state, .inProgress)

      server = UKey2Wrapper(role: .responder)
      var clientMessage = peripheralMock.writtenData[0]
      server.parseHandshakeMessage(clientMessage)

      let serverMesssage = server.nextHandshakeMessage()!

      simulateMessageFromServer(serverMesssage)

      clientMessage = peripheralMock.writtenData[1]
      server.parseHandshakeMessage(clientMessage)

      server.verificationData(withByteLength: 32)
      server.verifyHandshake()

      XCTAssertEqual(ukey2Channel.state, .resumingSession)

      ukey2Channel.messageStreamDidWriteMessage(
        ukey2Channel.messageStream!, to: Self.recipientUUID)

      var combinedSessionKey = Data()
      combinedSessionKey.append(serverKey)
      combinedSessionKey.append(server.uniqueSessionKey!)

      let resumptionSalt = Data("RESUME".utf8)
      let clientInfoPrefix = Data("CLIENT".utf8)

      let resumeHMAC = CryptoOps.hkdf(
        inputKeyMaterial: combinedSessionKey,
        salt: resumptionSalt,
        info: clientInfoPrefix
      )

      clientMessage = peripheralMock.writtenData[2]
      XCTAssertEqual(clientMessage, resumeHMAC)

      let serverInfoPrefix = Data("SERVER".utf8)
      let serverHMAC = CryptoOps.hkdf(
        inputKeyMaterial: combinedSessionKey,
        salt: resumptionSalt,
        info: serverInfoPrefix
      )!

      simulateMessageFromServer(serverHMAC)

      XCTAssertEqual(ukey2Channel.state, .established)
    }
  }

  // MARK: - Helper functions.

  /// Simulates to the `UKey2Channel` that the given `message` has been sent from the server.
  private func simulateMessageFromServer(_ message: Data) {
    ukey2Channel.messageStream(
      ukey2Channel.messageStream!,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: Self.recipientUUID,
        operationType: .encryptionHandshake
      )
    )
  }

  /// Runs through the encryption flow and ensures a secure channel is set up between the given
  /// client and peripheral.
  ///
  /// - Parameter:
  ///   - client: The `UKey2Channel` that handles secure connections. Represents the phone.
  ///   - operationType: The operation type to be used for messages from the peripheral.
  /// - Returns: The server instance, which just needs verification of its pairing code.
  @discardableResult
  private func setUpHandshake(client: UKey2Channel) -> UKey2Wrapper {
    XCTAssertNoThrow(try ukey2Channel.establish(using: messageStream))

    let server = UKey2Wrapper(role: .responder)

    var clientMessage = peripheralMock.writtenData[0]
    server.parseHandshakeMessage(clientMessage)

    let serverMesssage = server.nextHandshakeMessage()!

    // Send server message back down to client via the callback.
    ukey2Channel.messageStream(
      ukey2Channel.messageStream!,
      didReceiveMessage: serverMesssage,
      params: MessageStreamParams(
        recipient: Self.recipientUUID,
        operationType: .encryptionHandshake
      )
    )

    clientMessage = peripheralMock.writtenData[1]
    server.parseHandshakeMessage(clientMessage)

    // Ensure server is in verification mode.
    server.verificationData(withByteLength: 32)

    return server
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
