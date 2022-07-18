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
import CoreBluetooth
import XCTest
import AndroidAutoCompanionProtos

@testable import AndroidAutoMessageStream

private typealias Message = Com_Google_Companionprotos_Message
private typealias OperationType = Com_Google_Companionprotos_OperationType
private typealias Packet = Com_Google_Companionprotos_Packet

/// Unit tests for `BLEMessageStreamV2`.
class BLEMessageStreamV2Test: XCTestCase {
  private let recipientUUID = UUID(uuidString: "B75D6A81-635B-4560-BD8D-9CDF83F32AE7")!

  /// Valid characters for generating a random string for sending data.
  private let characters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"

  private let peripheralMock = PeripheralMock(name: "fake")

  private let readCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad1"), value: nil)

  private let writeCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad2"), value: nil)

  private var params: MessageStreamParams!
  private var delegate: MessageStreamDelegateMock!
  private var messageEncryptor: MessageEncryptorMock!
  private var messageStreamV2: BLEMessageStreamV2!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    MessageIDGenerator.shared.reset()
    peripheralMock.reset()
    readCharacteristic.value = nil
    writeCharacteristic.value = nil

    params = MessageStreamParams(
      recipient: recipientUUID,
      operationType: .clientMessage
    )

    messageStreamV2 = BLEMessageStreamV2(
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      messageCompressor: DataCompressorMock(),
      isCompressionEnabled: false
    )

    delegate = MessageStreamDelegateMock()
    messageStreamV2.delegate = delegate

    messageEncryptor = MessageEncryptorMock()
    messageStreamV2.messageEncryptor = messageEncryptor
  }

  // MARK: - Initialization tests.

  func testsBleMessageStream_SetsItselfAsPeripheralDelegate() {
    XCTAssert(peripheralMock.delegate === messageStreamV2)
  }

  func testsBleMessageStream_SetsNotifyOnReadCharacteristic() {
    XCTAssertTrue(peripheralMock.notifyValueCalled)
    XCTAssert(peripheralMock.characteristicToNotifyFor === readCharacteristic)
  }

  // MARK: - Received message tests.

  func testUpdateValue_messageFitsWithoutChunking() {
    let operation = OperationType.clientMessage
    let recipient = Data("id".utf8)
    let maxSize = 200

    peripheralMock.maximumWriteValueLength = maxSize
    let payload = makeMessage(length: 100)

    let deviceMessage = try! MessagePacketFactory.makeDeviceMessage(
      operation: operation,
      isPayloadEncrypted: true,
      payload: payload,
      originalSize: 0,
      recipient: recipient
    ).serializedData()

    let message = try! MessagePacketFactory.makePacket(
      messageID: 1,
      payload: deviceMessage,
      packetNumber: 1,
      totalPackets: 1
    ).serializedData()

    simulateMessageReceived(message, from: peripheralMock)

    XCTAssertEqual(messageEncryptor.decryptCalledCount, 1)
    XCTAssertEqual(delegate.didUpdateValueCalledCount, 1)
    XCTAssertEqual(delegate.updatedMessage, payload)
  }

  func testUpdateValue_messageNeedsToBeChunked() {
    let operation = OperationType.clientMessage
    let recipient = Data("id".utf8)

    // Make sure the payload can't fit into one chunk.
    let maxSize = 80
    let payload = makeMessage(length: 1000)

    let messages = try! MessagePacketFactory.makePackets(
      messageID: 1,
      operation: operation,
      payload: payload,
      originalSize: 0,
      isPayloadEncrypted: true,
      recipient: recipient,
      maxSize: maxSize
    )

    // Verify the message actually chunked.
    XCTAssertGreaterThan(messages.count, 1)

    peripheralMock.maximumWriteValueLength = maxSize

    // Notify for each chunk of the message.
    for message in messages {
      let message = try! message.serializedData()
      simulateMessageReceived(message, from: peripheralMock)
    }

    // Delegate should only be called once, and only to be notified of the complete message.
    XCTAssertEqual(delegate.didUpdateValueCalledCount, 1)
    XCTAssertEqual(delegate.updatedMessage, payload)
    XCTAssertEqual(messageEncryptor.decryptCalledCount, 1)
  }

  func testUpdateValue_correctlyPassesParams() {
    let operation = OperationType.clientMessage
    let recipientUUID = UUID()
    let recipient = withUnsafeBytes(of: recipientUUID.uuid, { Data($0) })
    let maxSize = 200

    peripheralMock.maximumWriteValueLength = maxSize
    let payload = makeMessage(length: 100)

    let deviceMessage = try! MessagePacketFactory.makeDeviceMessage(
      operation: operation,
      isPayloadEncrypted: true,
      payload: payload,
      originalSize: 0,
      recipient: recipient
    ).serializedData()

    let message = try! MessagePacketFactory.makePacket(
      messageID: 1,
      payload: deviceMessage,
      packetNumber: 1,
      totalPackets: 1
    ).serializedData()

    simulateMessageReceived(message, from: peripheralMock)

    let params = delegate.receivedMessageParams
    XCTAssertNotNil(params)
    XCTAssertEqual(params!.recipient, recipientUUID)
    XCTAssertEqual(params!.operationType, operation.toStreamOperationType())
  }

  // MARK: - Duplicate message test

  func testDuplicatePacketIsIgnored() {
    let operation = OperationType.clientMessage
    let recipient = Data("id".utf8)

    // Make sure the payload can't fit into one chunk.
    let maxSize = 80
    let payload = makeMessage(length: 1000)

    let messages = try! MessagePacketFactory.makePackets(
      messageID: 1,
      operation: operation,
      payload: payload,
      originalSize: 0,
      isPayloadEncrypted: true,
      recipient: recipient,
      maxSize: maxSize
    )

    // Verify the message actually chunked.
    XCTAssertGreaterThan(messages.count, 1)

    peripheralMock.maximumWriteValueLength = maxSize

    // Notify for each chunk of the message.
    for message in messages {
      let message = try! message.serializedData()

      // Note: Calling `didUpdateValue` twice for each message to simulate a duplicate packet.
      simulateMessageReceived(message, from: peripheralMock)
      simulateMessageReceived(message, from: peripheralMock)
    }

    // Delegate should only be called once, and only to be notified of the complete message.
    XCTAssertEqual(delegate.didUpdateValueCalledCount, 1)
    XCTAssertEqual(delegate.updatedMessage, payload)
    XCTAssertEqual(messageEncryptor.decryptCalledCount, 1)

    XCTAssertFalse(delegate.encounteredUnrecoverableErrorCalled)
  }

  // MARK: - Out-of-order message test

  func testOutOfOrderMessage_notifiesDelegateOfError() {
    let operation = OperationType.clientMessage
    let recipient = Data("id".utf8)

    // Make sure the payload can't fit into one chunk.
    let maxSize = 80
    let payload = makeMessage(length: 1000)

    let messages = try! MessagePacketFactory.makePackets(
      messageID: 1,
      operation: operation,
      payload: payload,
      originalSize: 0,
      isPayloadEncrypted: true,
      recipient: recipient,
      maxSize: maxSize
    )

    peripheralMock.maximumWriteValueLength = maxSize

    // Verify that we can simulate the first and last message being out-of-order.
    XCTAssertGreaterThan(messages.count, 2)

    let firstMessage = try! messages.first!.serializedData()
    simulateMessageReceived(firstMessage, from: peripheralMock)
    let lastMessage = try! messages.last!.serializedData()
    simulateMessageReceived(lastMessage, from: peripheralMock)

    XCTAssertEqual(delegate.didUpdateValueCalledCount, 0)
    XCTAssertTrue(delegate.encounteredUnrecoverableErrorCalled)
  }
  // MARK: - writeMessage() tests.

  func testWriteMessage_fitsWithoutChunkingNotifiesDelegate() {
    assertWriteMessage_fitsWithoutChunkingNotifiesDelegate(isEncryptedWrite: false)
  }

  func testWriteMessage_fitsWithoutChunkingCorrectlySplitsPayload() {
    assertWriteMessage_fitsWithoutChunkingCorrectlySplitsPayload(isEncryptedWrite: false)
  }

  func testWriteMessage_requiresChunkingOnlyNotifiesAfterCompleteMessageSent() {
    assertWriteMessage_requiresChunkingOnlyNotifiesAfterCompleteMessageSent(isEncryptedWrite: false)
  }

  func testWriteMessage_requiresChunkingCorrectlySplitsPayload() {
    assertWriteMessage_requiresChunkingCorrectlySplitsPayload(isEncryptedWrite: false)
  }

  func testWriteMessage_waitsIfSendInProgress() {
    assertWriteMessage_waitsIfSendInProgresss(isEncryptedWrite: false)
  }

  func testWriteCompressedMessage_requiresChunkingCorrectlySplitsPayload() {
    messageStreamV2 = BLEMessageStreamV2(
      peripheral: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      messageCompressor: DataCompressorMock(),
      isCompressionEnabled: true
    )
    assertWriteMessage_requiresChunkingCorrectlySplitsPayload(isEncryptedWrite: false)
  }

  // MARK: - writeEncryptedMessage() tests.

  func testWriteEncryptedMessage_fitsWithoutChunkingNotifiesDelegate() {
    assertWriteMessage_fitsWithoutChunkingNotifiesDelegate(isEncryptedWrite: true)
  }

  func testWriteEncryptedMessage_fitsWithoutChunkingCorrectlySplitsPayload() {
    assertWriteMessage_fitsWithoutChunkingCorrectlySplitsPayload(isEncryptedWrite: true)
  }

  func testWriteEncryptedMessage_requiresChunkingOnlyNotifiesAfterCompleteMessageSent() {
    assertWriteMessage_requiresChunkingOnlyNotifiesAfterCompleteMessageSent(isEncryptedWrite: true)
  }

  func testWriteEncryptedMessage_requiresChunkingCorrectlySplitsPayload() {
    assertWriteMessage_requiresChunkingCorrectlySplitsPayload(isEncryptedWrite: true)
  }

  func testWriteEncryptedMessage_waitsIfSendInProgress() {
    assertWriteMessage_waitsIfSendInProgresss(isEncryptedWrite: true)
  }

  // MARK: - Error state tests.

  func testWriteEncryptedMessage_throwsErrorIfNoMessageEncryptor() {
    let message = Data("arbitrary_message".utf8)
    messageStreamV2.messageEncryptor = nil

    XCTAssertThrowsError(
      try messageStreamV2.writeEncryptedMessage(message, params: params)
    ) { error in
      XCTAssertEqual(error as? BLEMessageStreamV2Error, BLEMessageStreamV2Error.noEncryptorSet)
    }
  }

  func testWriteEncryptedMessage_throwsErrorIfEncryptionFails() {
    let message = Data("arbitrary_message".utf8)
    messageEncryptor.canEncrypt = false

    XCTAssertThrowsError(
      try messageStreamV2.writeEncryptedMessage(message, params: params)
    ) { error in
      XCTAssertEqual(error as? BLEMessageStreamV2Error, BLEMessageStreamV2Error.cannotEncrypt)
    }
  }

  // MARK: - Maximum write length test

  func testMaximumWriteValueLength_constrainedToMaxValue() {
    // Ensure that the reported max size is greater than the max size in the stream.
    peripheralMock.maximumWriteValueLength = BLEMessageStreamV2.maxWriteValueLength + 1000

    // Create a message that would have fit with the extra space.
    let message = makeMessage(length: 200)
    XCTAssertNoThrow(try messageStreamV2.writeMessage(message, params: params))

    // Verify at least once message written to the peripheral.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    XCTAssertEqual(peripheralMock.characteristicWrittenTo.count, 1)
    XCTAssert(peripheralMock.characteristicWrittenTo[0] === writeCharacteristic)
    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    // The written message should be a proto.
    let proto = try! Packet(serializedData: peripheralMock.writtenData[0])

    // The proto should have been chunked.
    XCTAssertEqual(proto.packetNumber, 1)
    XCTAssertGreaterThan(proto.totalPackets, 1)
  }

  // MARK: - Common test assertions

  private func assertWriteMessage_fitsWithoutChunkingNotifiesDelegate(isEncryptedWrite: Bool) {
    // Ensure the message fits.
    peripheralMock.maximumWriteValueLength = BLEMessageStreamV2.maxWriteValueLength
    let message = makeMessage(length: 50)

    writeMessage(message, isEncryptedWrite: isEncryptedWrite)

    // Simulate the response that the write was successful.
    notifyReadyToWrite(forCount: 1)

    // Delegate should only be called once.
    XCTAssertEqual(delegate.didWriteMessageCalledCount, 1)
  }

  private func assertWriteMessage_fitsWithoutChunkingCorrectlySplitsPayload(
    isEncryptedWrite: Bool
  ) {
    // Ensure the message fits.
    peripheralMock.maximumWriteValueLength = BLEMessageStreamV2.maxWriteValueLength
    let message = makeMessage(length: 50)

    writeMessage(message, isEncryptedWrite: isEncryptedWrite)

    // Simulate the response that the write was successful.
    notifyReadyToWrite(forCount: 1)

    assertWrittenMessageCorrect(on: peripheralMock, expectedMessage: message)
  }

  private func assertWriteMessage_requiresChunkingOnlyNotifiesAfterCompleteMessageSent(
    isEncryptedWrite: Bool
  ) {
    // Set a message ID to make testing easier.
    let messageID: Int32 = 5
    MessageIDGenerator.shared.messageID = messageID

    // Ensure the message does not fit in 1 message.
    peripheralMock.maximumWriteValueLength = 182
    let message = makeMessage(length: 1000)

    writeMessage(message, isEncryptedWrite: isEncryptedWrite)

    let requiredWrites = messageStreamV2.writeMessageStack.count

    // Double check that message needs to be chunked.
    XCTAssertGreaterThan(requiredWrites, 1)

    // Should receive acknowledgment for each write.
    notifyReadyToWrite(forCount: requiredWrites)

    // The delegate should only be called once though.
    XCTAssertEqual(delegate.didWriteMessageCalledCount, 1)
  }

  private func assertWriteMessage_requiresChunkingCorrectlySplitsPayload(
    isEncryptedWrite: Bool
  ) {
    // Set a message ID to make testing easier.
    let messageID: Int32 = 5
    MessageIDGenerator.shared.messageID = messageID

    // Ensure the message does not fit in 1 message.
    peripheralMock.maximumWriteValueLength = 182
    let message = makeMessage(length: 1000)

    writeMessage(message, isEncryptedWrite: isEncryptedWrite)

    let requiredWrites = messageStreamV2.writeMessageStack.count

    // Double check that message needs to be chunked.
    XCTAssertGreaterThan(requiredWrites, 1)

    // Should receive acknowledgment for each write.
    notifyReadyToWrite(forCount: requiredWrites)

    assertChunkedMessageHeaderCorrect(
      on: peripheralMock,
      expectedWriteCount: requiredWrites,
      messageID: messageID
    )

    assertChunkedMessagePayloadCorrect(
      on: peripheralMock,
      expectedWriteCount: requiredWrites,
      expectedPayload: message,
      isEncrypted: isEncryptedWrite
    )
  }

  private func assertWriteMessage_waitsIfSendInProgresss(isEncryptedWrite: Bool) {
    // Ensure the message does not fit in 1 message.
    peripheralMock.maximumWriteValueLength = 182
    let message = makeMessage(length: 1000)

    writeMessage(message, isEncryptedWrite: isEncryptedWrite)

    let requiredWrites = messageStreamV2.writeMessageStack.count

    // Double check that message needs to be chunked.
    XCTAssertGreaterThan(requiredWrites, 1)

    // A message should have been written to the peripheral
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)

    // Now call write again for a different message
    let secondMessage = makeMessage(length: 1000)
    writeMessage(secondMessage, isEncryptedWrite: isEncryptedWrite, expectedEncryptorCalledCount: 2)

    // Since we did not send a write confirmation, there should not be a second write yet.
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)

    // Now send the notification and verify the write.
    notifyReadyToWrite(forCount: 1)
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 2)
  }

  /// Asserts that the state of the given message stream after a `writeMessage` was called.
  private func assertWrittenMessageCorrect(
    on peripheralMock: PeripheralMock,
    expectedMessage: Data
  ) {
    XCTAssertEqual(peripheralMock.writeValueCalledCount, 1)
    XCTAssertEqual(peripheralMock.characteristicWrittenTo.count, 1)
    XCTAssert(peripheralMock.characteristicWrittenTo[0] === writeCharacteristic)
    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    // The written data should be a proto.
    let blePacket = try! Packet(serializedData: peripheralMock.writtenData[0])

    // The proto should say that there's only 1 packet.
    XCTAssertEqual(blePacket.packetNumber, 1)
    XCTAssertEqual(blePacket.totalPackets, 1)

    let deviceMessage = try! Message(serializedData: blePacket.payload)
    let payload: Data
    if messageStreamV2.isCompressionEnabled,
      let messageCompressor = messageStreamV2.messageCompressor as? DataCompressorMock
    {
      XCTAssertTrue(messageCompressor.compressCalled)
      let originalSize = Int(deviceMessage.originalSize)
      payload = messageCompressor.decompress(deviceMessage.payload, originalSize: originalSize)
    } else {
      payload = deviceMessage.payload
    }

    XCTAssertEqual(payload, expectedMessage)
  }

  /// Asserts that the header of the `MessagePacket` has the correct packet numbers up to the given
  /// write count and message ID.
  private func assertChunkedMessageHeaderCorrect(
    on peripheralMock: PeripheralMock,
    expectedWriteCount: Int,
    messageID: Int32
  ) {
    XCTAssertEqual(peripheralMock.writeValueCalledCount, expectedWriteCount)
    XCTAssertEqual(peripheralMock.characteristicWrittenTo.count, expectedWriteCount)

    for characteristic in peripheralMock.characteristicWrittenTo {
      XCTAssert(characteristic === writeCharacteristic)
    }

    XCTAssertEqual(peripheralMock.writtenData.count, expectedWriteCount)

    // Check the packet numbers of each write.
    for index in 0..<expectedWriteCount {
      let blePacket = try! Packet(serializedData: peripheralMock.writtenData[index])

      // Adding 1 to the index since the packet number is 1-based.
      XCTAssertEqual(blePacket.packetNumber, UInt32(index + 1))
      XCTAssertEqual(blePacket.totalPackets, Int32(expectedWriteCount))
      XCTAssertEqual(blePacket.messageID, messageID)
    }
  }

  /// Asserts that the reconstructed payload of all the `MessagePacket`s matches the given
  /// `expectedPayload`.
  private func assertChunkedMessagePayloadCorrect(
    on peripheralMock: PeripheralMock,
    expectedWriteCount: Int,
    expectedPayload: Data,
    isEncrypted: Bool
  ) {
    XCTAssertEqual(peripheralMock.writtenData.count, expectedWriteCount)

    var packetPayload = Data()
    for writtenData in peripheralMock.writtenData {
      let blePacket = try! Packet(serializedData: writtenData)
      packetPayload.append(blePacket.payload)
    }

    let deviceMessage = try! Com_Google_Companionprotos_Message(
      serializedData: packetPayload)

    XCTAssertEqual(deviceMessage.isPayloadEncrypted, isEncrypted)

    // The message compressor will change the payload.
    if !messageStreamV2.isCompressionEnabled {
      XCTAssertEqual(deviceMessage.payload, expectedPayload)
    }

    let expectedRecipient = withUnsafeBytes(of: recipientUUID) { Data($0) }
    XCTAssertEqual(deviceMessage.recipient, expectedRecipient)
  }

  // MARK: - Helper functions

  private func writeMessage(
    _ message: Data,
    isEncryptedWrite: Bool,
    expectedEncryptorCalledCount: Int = 1
  ) {
    if isEncryptedWrite {
      XCTAssertNoThrow(try messageStreamV2.writeEncryptedMessage(message, params: params))
      XCTAssertEqual(messageEncryptor.encryptCalledCount, expectedEncryptorCalledCount)
    } else {
      XCTAssertNoThrow(try messageStreamV2.writeMessage(message, params: params))
      XCTAssertEqual(messageEncryptor.encryptCalledCount, 0)
    }
  }

  private func simulateMessageReceived(_ message: Data, from peripheral: PeripheralMock) {
    readCharacteristic.value = message

    messageStreamV2.peripheral(
      peripheral,
      didUpdateValueFor: readCharacteristic,
      error: nil
    )
  }

  /// Notifies that the current peripheral is ready to send another message.
  private func notifyReadyToWrite(forCount count: Int) {
    for _ in 1...count {
      messageStreamV2.peripheralIsReadyToWrite(peripheralMock)
    }
  }

  /// Returns a `Data` object that holds a random string of the given length.
  private func makeMessage(length: Int) -> Data {
    return Data(
      String(
        (0..<length).map { _ in
          characters.randomElement()!
        }
      ).utf8
    )
  }
}
