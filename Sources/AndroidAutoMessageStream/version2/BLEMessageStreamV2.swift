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
import AndroidAutoLogger
import CoreBluetooth
import Foundation
import AndroidAutoCompanionProtos

private typealias BleDeviceMessage = Com_Google_Companionprotos_Message
private typealias MessagePacket = Com_Google_Companionprotos_Packet

/// Represents a message that the car has sent.
///
/// This message could be a partial message; that is, the car is still sending packets that will
/// need to be reconstructed for the full message.
///
/// The `payload` is the raw data that has been received so far. New packets are appended to the
/// end of this `Data` object. `lastPacketNumber` is the packet number of the last message that was
/// appended to `payload`.
private typealias ReceivedMessage = (
  payload: Data,
  lastPacketNumber: UInt32
)

/// Errors that can occur within the message stream.
enum BLEMessageStreamV2Error: Error {
  /// An error occurred during the serialization of a message for write.
  case cannotSerializeMessage

  /// No `messageEncryptor` was set on this stream, meaning that a message cannot be encrypted for
  /// sending or a message received from a remote peripheral cannot be decrypted.
  case noEncryptorSet

  /// There was an error during the encryption of a message.
  case cannotEncrypt

  /// There was an error during the decryption of a message.
  case cannotDecrypt

  /// Failed to decompress a compressed message.
  case cannotDecompress
}

/// An extension of the error that sets a message describing the cause.
extension BLEMessageStreamV2Error: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .cannotSerializeMessage:
      return "Cannot serialize the message to be sent to the peripheral."
    case .noEncryptorSet:
      return "No messageEncryptor set on this stream."
    case .cannotEncrypt:
      return "Message cannot be encrypted for sending"
    case .cannotDecrypt:
      return "Cannot decrypt message from remote peripheral."
    case .cannotDecompress:
      return "Cannot decrompess the compressed message from the remote peripheral."
    }
  }
}

/// Version 2 of the message stream.
class BLEMessageStreamV2: NSObject {
  private static let log = Logger(for: BLEMessageStreamV2.self)

  /// The maximum number of bytes that can be sent each time across BLE.
  ///
  /// iOS devices greater than version 11 will request a value of 185 bytes. Even if an MTU size is
  /// ultimately resolved to be larger than this value, iOS will still chunk messages in sizes of
  /// 185.
  ///
  /// However, this number is 182 because 3 bytes are used by the attribute protocol to encode the
  /// command type and attribute ID and need to be subtracted from the write length.
  static let maxWriteValueLength = 182

  /// Messages that should be written to the write characteristic.
  ///
  /// The messages are ordered so that the item at the end of the array is the first message that
  /// should be written.
  ///
  /// A stack is used instead of a queue because the `removeFirst` operation of an array is O(N)
  /// while `removeLast` is O(1).
  var writeMessageStack: [Com_Google_Companionprotos_Packet] = []

  /// Keeps track of messages that are still waiting to be written.
  ///
  /// This map has the message ID as its key and the recipient UUID as its value. Entries are
  /// removed from this map upon a successful write.
  private var pendingMessages: [Int32: UUID] = [:]

  /// Messages that have been received from the read characteristic.
  ///
  /// This dictionary maps `messageID` to messages that the car has sent. This message is a tuple
  /// of the raw message data and the package number of the last message that was appended to create
  /// that data.
  private var receivedMessages: [Int32: ReceivedMessage] = [:]

  /// Whether a `writeValue` to the remote peripheral is currently in progress.
  ///
  /// This value is toggled to true when a `writeValue` is called and toggled back when the this
  /// stream has received confirmation that the write was successful.
  private var isWriteInProgress = false

  /// Indicates whether outgoing messages should be compressed.
  let isCompressionEnabled: Bool

  /// Data compressor for compressing messages.
  let messageCompressor: DataCompressor

  public var version: MessageStreamVersion {
    MessageStreamVersion.v2(true)
  }

  public let peripheral: BLEPeripheral
  public let readCharacteristic: BLECharacteristic
  public let writeCharacteristic: BLECharacteristic

  /// Determine whether this stream is still valid for reading and writing.
  var isValid: Bool {
    guard let readServiceUUID = readCharacteristic.serviceUUID else { return false }
    guard let writeServiceUUID = writeCharacteristic.serviceUUID else { return false }

    return !peripheral.isServiceInvalidated(uuids: [readServiceUUID, writeServiceUUID])
  }

  /// The encryptor responsible for encrypting and decrypting messages.
  public var messageEncryptor: MessageEncryptor?

  public weak var delegate: MessageStreamDelegate?

  /// Debug description for reading.
  var readingDebugDescription: String {
    "Read characteristic with uuid: \(readCharacteristic.uuid.uuidString)"
  }

  /// Debug description for writing.
  var writingDebugDescription: String {
    "Write characteristic with uuid: \(writeCharacteristic.uuid.uuidString)"
  }

  /// Creates a stream with the given peripheral.
  ///
  /// - Parameters
  ///   - peripheral: The peripheral to stream messages with.
  ///   - readCharacteristic: The characteristic to listen for new messages on.
  ///   - writeCharacteristic: The characteristic to write messages to.
  ///   - messageCompressor: Compresses/decompresses message data.
  ///   - isCompressionEnabled: Whether outgoing messages should be compressed.
  public init(
    peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic,
    messageCompressor: DataCompressor,
    isCompressionEnabled: Bool
  ) {
    self.peripheral = peripheral
    self.readCharacteristic = readCharacteristic
    self.writeCharacteristic = writeCharacteristic
    self.messageCompressor = messageCompressor
    self.isCompressionEnabled = isCompressionEnabled

    // "self" can only be used for something other than referencing fields after init() has been
    // called.
    super.init()
    peripheral.delegate = self
    peripheral.setNotifyValue(true, for: readCharacteristic)
  }

  /// Write the message encrypting it if indicated.
  private func writeMessage(
    _ message: Data,
    encrypting: Bool,
    params: MessageStreamParams
  ) throws {
    // Attempt to compress the message if allowed.
    let outputMessage: Data
    let originalSize: UInt32
    if isCompressionEnabled, let compressedMessage = try? messageCompressor.compress(message) {
      originalSize = UInt32(message.count)
      outputMessage = compressedMessage
    } else {
      // Pass original size of zero to indicate the message wasn't compressed.
      originalSize = 0
      outputMessage = message
    }

    // Encrypt the message if indicated.
    if encrypting {
      try writeMessage(
        try encryptMessage(outputMessage),
        isEncrypted: true,
        originalSize: originalSize,
        params: params
      )
    } else {
      try writeMessage(
        outputMessage, isEncrypted: false, originalSize: originalSize, params: params)
    }
  }

  private func writeMessage(
    _ message: Data,
    isEncrypted: Bool,
    originalSize: UInt32,
    params: MessageStreamParams
  ) throws {
    let reportedMaxWriteLength = peripheral.maximumWriteValueLength
    let maximumWriteValueLength = min(
      BLEMessageStreamV2.maxWriteValueLength,
      reportedMaxWriteLength
    )

    Self.log.debug(
      """
      Write message of length: \(message.count), \
      maximumWriteValueLength: \(maximumWriteValueLength)
      """
    )

    // No recipient to encode for encryption handshakes, so use an empty `Data` object instead.
    // This value cannot be `nil` because the proto does not except `nil` values.
    let recipientBytes =
      params.operationType == .encryptionHandshake
      ? Data() : withUnsafeBytes(of: params.recipient.uuid) { Data($0) }

    let messageID = MessageIDGenerator.shared.next()
    var newPackets: [MessagePacket]
    do {
      newPackets = try MessagePacketFactory.makePackets(
        messageID: messageID,
        operation: params.operationType.toOperationType(),
        payload: message,
        originalSize: originalSize,
        isPayloadEncrypted: isEncrypted,
        recipient: recipientBytes,
        maxSize: maximumWriteValueLength
      )
    } catch {
      Self.log.error(
        "Error during attempt to chunk message for sending: \(error.localizedDescription)")
      throw BLEMessageStreamV2Error.cannotSerializeMessage
    }

    Self.log.info("Number of chunks for streaming message: \(newPackets.count)")

    // Reversing so that the first message to send will be at the end. This ensures that we can
    // call removeLast() rather than removeFirst(), the latter of which is an O(n) operation.
    // This will incur a one-time O(n) cost rather than per-message.
    newPackets.reverse()

    // Inserting at the start of the stack. This will also incur a one-time O(n+m) cost where n
    // is the length of `writeMessageStack` and m is the length of `newPackets`.
    writeMessageStack.insert(contentsOf: newPackets, at: 0)

    // Keep track of messages that still need to be written.
    pendingMessages[messageID] = params.recipient

    writeNextMessageInStack()
  }

  private func writeNextMessageInStack() {
    guard !isWriteInProgress else {
      Self.log.info(
        "Request to write next message, but a write is currently in progress. Will wait.")
      return
    }

    guard let blePacket = writeMessageStack.last else {
      Self.log.error(
        "Requested to write next message to peripheral, but no remaining messages to be written.")
      return
    }

    do {
      let serializedMessage = try blePacket.serializedData()
      peripheral.writeValue(serializedMessage, for: writeCharacteristic)
      isWriteInProgress = true

      Self.log.info(
        """
        Writing packet \(blePacket.packetNumber) of \(blePacket.totalPackets). \
        Message ID: \(blePacket.messageID).
        """
      )
    } catch {
      Self.log.error("Error serializing message for sending: \(error.localizedDescription)")

      // This should not happen because every message should have a recipient.
      guard let recipient = pendingMessages[blePacket.messageID] else {
        Self.log.error(
          """
          Unexpected. No recipient for messageID: \(blePacket.messageID). \
          Cannot notify of write error.
          """
        )
        return
      }

      notifyWriteError(
        BLEMessageStreamV2Error.cannotSerializeMessage,
        for: recipient,
        characteristic: writeCharacteristic
      )
    }
  }

  private func processReceivedPacket(_ blePacket: MessagePacket) {
    let messageID = blePacket.messageID

    let receivedMessage: ReceivedMessage
    if let lastReceivedMessage = receivedMessages[messageID] {
      guard isValid(blePacket, lastReceivedMessage: lastReceivedMessage) else { return }
      receivedMessage = blePacket.toReceivedMessage(prependingPayloadFrom: lastReceivedMessage)
    } else {
      // The first message must start at 1, but handle receiving the last packet as this could
      // represent a duplicate packet. All other cases will trigger an exception when the packet
      // is parsed into a `BleDeviceMessage`.
      if blePacket.packetNumber != 1, blePacket.packetNumber == blePacket.totalPackets {
        Self.log(
          """
          Received possible duplicate last packet. \
          MessagePacket number \(blePacket.packetNumber), message ID: \(messageID)
          """
        )
        return
      }
      receivedMessage = blePacket.toReceivedMessage()
    }

    receivedMessages[messageID] = receivedMessage

    // Only notify delegate if the message is complete.
    guard blePacket.packetNumber == blePacket.totalPackets else { return }

    handleCompletePayload(receivedMessage.payload, messageID: messageID)
  }

  /// Returns `true` if the given packet is valid based on the specified `lastReceivedMessage`.
  private func isValid(_ blePacket: MessagePacket, lastReceivedMessage: ReceivedMessage) -> Bool {
    if lastReceivedMessage.lastPacketNumber + 1 == blePacket.packetNumber {
      return true
    }

    // A duplicate packet can just be ignored, while an out-of-order packet should notify the
    // delegate that the stream should be closed.
    if lastReceivedMessage.lastPacketNumber == blePacket.packetNumber {
      Self.log("Received a duplicate packet (\(blePacket.packetNumber)). Ignoring.")
    } else {
      Self.log.error(
        """
        Received out-of-order packet \(blePacket.packetNumber). \
        Expecting \(lastReceivedMessage.lastPacketNumber + 1).
        """
      )

      delegate?.messageStreamEncounteredUnrecoverableError(self)
    }

    return false
  }

  private func handleCompletePayload(_ payload: Data, messageID: Int32) {
    receivedMessages[messageID] = nil

    guard let deviceMessage = try? BleDeviceMessage(serializedData: payload) else {
      Self.log.error(
        "Unable to deserialize received message (id: \(messageID)) into a BleDeviceMessage")
      delegate?.messageStreamEncounteredUnrecoverableError(self)
      return
    }

    // Decrypt the device message payload if it's encrypted.
    var payload: Data
    if deviceMessage.isPayloadEncrypted {
      do {
        payload = try decryptMessage(deviceMessage.payload)
      } catch {
        Self.log.error(
          "Unable to decrypt message with ID: \(messageID) reason: \(error.localizedDescription)")
        delegate?.messageStreamEncounteredUnrecoverableError(self)
        return
      }
    } else {
      payload = deviceMessage.payload
    }

    // Decompress the payload if necessary.
    do {
      try decompressPayloadIfNeeded(&payload, originalSize: Int(deviceMessage.originalSize))
    } catch {
      Self.log.error("Unable to decompress message for ID: \(messageID)")
      delegate?.messageStreamEncounteredUnrecoverableError(self)
      return
    }

    delegate?.messageStream(
      self,
      didReceiveMessage: payload,
      params: MessageStreamParams(
        recipient: NSUUID(uuidBytes: [UInt8](deviceMessage.recipient)) as UUID,
        operationType: deviceMessage.operation.toStreamOperationType()
      )
    )
  }

  // Decompress the payload if it's compressed which is indicated by nonzero `originalSize`.
  private func decompressPayloadIfNeeded(_ payload: inout Data, originalSize: Int) throws {
    if originalSize > 0 {
      payload = try messageCompressor.decompress(payload, originalSize: originalSize)
    }
  }

  private func notifyWriteError(
    _ error: Error,
    for recipient: UUID,
    characteristic: BLECharacteristic
  ) {
    Self.log.error(
      """
      Error during write for characteristic (\(characteristic.uuid.uuidString)): \
      \(error.localizedDescription)
      """
    )

    delegate?.messageStream(self, didEncounterWriteError: error, to: recipient)
  }

  private func encryptMessage(_ message: Data) throws -> Data {
    guard let messageEncryptor = messageEncryptor else {
      throw BLEMessageStreamV2Error.noEncryptorSet
    }

    guard let encryptedMessage = try? messageEncryptor.encrypt(message) else {
      throw BLEMessageStreamV2Error.cannotEncrypt
    }

    return encryptedMessage
  }

  private func decryptMessage(_ message: Data) throws -> Data {
    guard let messageEncryptor = messageEncryptor else {
      throw BLEMessageStreamV2Error.noEncryptorSet
    }

    guard let decryptedMessage = try? messageEncryptor.decrypt(message) else {
      throw BLEMessageStreamV2Error.cannotDecrypt
    }

    return decryptedMessage
  }
}

// MARK: - BLEMessageStream

extension BLEMessageStreamV2: BLEMessageStream {
  /// Writes the given message to the peripheral associated with this stream.
  ///
  /// Upon completion of the write, the `delegate` of this class will be notified via a call to
  /// `messageStreamV2(_:didWriteMessageFor:error)`.
  ///
  /// If a write is called again before a previous write has finished, then the first write will be
  /// canceled.
  ///
  /// - Parameter message: The message to write.
  public func writeMessage(_ message: Data, params: MessageStreamParams) throws {
    try writeMessage(message, encrypting: false, params: params)
  }

  /// Encrypts and writes the given message to the peripheral associated with this stream.
  ///
  /// For the message to be encrypted properly, a `messageEncryptor` should be set on this stream.
  /// If no encryptor is set, or there was an error during encryption, then this method will
  /// throw an error.
  ///
  /// - Parameter message: The message to write.
  /// - Throws: An error occurred during the encryption of the message.
  public func writeEncryptedMessage(_ message: Data, params: MessageStreamParams) throws {
    try writeMessage(message, encrypting: true, params: params)
  }
}

// MARK: - BLEPeripheralDelegate

extension BLEMessageStreamV2: BLEPeripheralDelegate {
  public func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    guard error == nil else {
      Self.log.error("Error on characteristic update: \(error!.localizedDescription)")
      return
    }

    // This should never happen because we only call `setNotifyValue` for this characteristic.
    guard characteristic.uuid == readCharacteristic.uuid else {
      Self.log.error(
        """
        Received a message from an unexpected characteristic \
        (\(characteristic.uuid.uuidString)). Expected \(readCharacteristic.uuid.uuidString).
        """
      )
      return
    }

    guard let message = characteristic.value else {
      // An empty message is not necessarily an error. Just ignore and see if the characteristic
      // updates to a valid one.
      Self.log.debug("Received empty message from characteristic \(characteristic.uuid.uuidString)")
      return
    }

    guard let blePacket = try? MessagePacket(serializedData: message) else {
      Self.log.error(
        """
        Received message for characteristic (\(characteristic.uuid.uuidString)), \
        but could not parse.
        """
      )
      return
    }

    Self.log.info(
      """
      Received message for readCharacteristic (\(readCharacteristic.uuid.uuidString)). \
      Packet \(blePacket.packetNumber) of \(blePacket.totalPackets). \
      Message ID: \(blePacket.messageID)
      """
    )

    processReceivedPacket(blePacket)
  }

  func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral) {
    isWriteInProgress = false

    // This error shouldn't happen because we do not remove messages from the stack until there
    // is confirmation of a successful write. There should also always be a recipient.
    guard let blePacket = writeMessageStack.last,
      let recipient = pendingMessages[blePacket.messageID]
    else {
      Self.log.error(
        "Unexpected. Message write successful, but no message in the stack or recipient")
      return
    }

    // Write successful, remove the last message. This call will always succeed because we have
    // already checked that the stack was not empty.
    writeMessageStack.removeLast()

    Self.log.info(
      """
      Successfully wrote packet \(blePacket.packetNumber) of \(blePacket.totalPackets). \
      Message ID: \(blePacket.messageID). Remaining message: \(writeMessageStack.count)
      """
    )

    if blePacket.packetNumber == blePacket.totalPackets {
      delegate?.messageStreamDidWriteMessage(self, to: recipient)
    }

    // Continue writing packets if there are still some to write.
    if !writeMessageStack.isEmpty {
      writeNextMessageInStack()
    }
  }

  public func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?) {
    // No-op. Not discovering services in this class.
  }

  public func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  ) {
    // No-op. Not discovering characteristics in this class.
  }
}

// MARK: - MessagePacket extension.

extension MessagePacket {
  fileprivate func toReceivedMessage() -> ReceivedMessage {
    return (payload: payload, lastPacketNumber: packetNumber)
  }

  /// Returns a `ReceivedMessage` representation of this packet whose payload is a combination
  /// of the given `ReceivedMessage` and this packet's payload.
  fileprivate func toReceivedMessage(
    prependingPayloadFrom receivedMessage: ReceivedMessage
  ) -> ReceivedMessage {
    var newPayload = Data(receivedMessage.payload)
    newPayload.append(payload)

    return (payload: newPayload, lastPacketNumber: packetNumber)
  }
}
