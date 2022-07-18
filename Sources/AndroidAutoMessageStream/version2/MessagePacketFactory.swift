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

import AndroidAutoLogger
import Foundation
import AndroidAutoCompanionProtos

/// Possible errors that can result from creating a BLE packet.
enum MessagePacketFactoryError: Error {
  /// There was an error forming a wrapper around the data to sent.
  case cannotFormMessage

  /// The given data is too large to send with the current protos.
  case payloadTooLarge
}

/// A creator of `MessagePacket`s.
enum MessagePacketFactory {
  private static let log = Logger(for: MessagePacketFactory.self)

  /// The size in bytes of a `fixed32` field in the proto.
  private static let fixed32Size = 4

  /// The bytes needed to encode the field number in the proto.
  ///
  /// Since the packet proto only has 4 fields, it will only take 1 additional byte to encode. This
  /// size should be added for every field in the proto.
  private static let fieldNumberEncodingSize = 1

  /// The bytes needed to encode the packet number.
  ///
  /// The packet number is a `fixed32`, meaning that its size is constant.
  static let packetNumberEncodingSize = fixed32Size + fieldNumberEncodingSize

  /// Creates a `MessagePacket` from the given data.
  ///
  /// `MessagePacket`s that share the same `messageID` represent packets whose payloads can be
  /// combined together to create a complete message.
  ///
  /// - Parameters:
  ///   - messageID: A unique ID for this packet.
  ///   - payload: The data of this packet.
  ///   - packetNumber: A 1-based packet number.
  ///   - totalPacket: The total number of packets that combine together into a complete message.
  static func makePacket(
    messageID: Int32,
    payload: Data,
    packetNumber: UInt32 = 1,
    totalPackets: Int32 = 1
  ) -> Com_Google_Companionprotos_Packet {
    var packet = Com_Google_Companionprotos_Packet()

    packet.messageID = messageID
    packet.payload = payload
    packet.packetNumber = packetNumber
    packet.totalPackets = totalPackets

    return packet
  }

  /// Returns a list of `MessagePacket`s where each item is at most the given `maxSize` and whose
  /// `payload`s together house the given `payload`.
  ///
  /// The list is ordered sequentially where the first item is the first packet.
  ///
  /// - Complexity: O(*n*), where *n* is the length of the payload.
  /// - Parameters:
  ///   - operation: The operation this message represents.
  ///   - payload: The payload to send.
  /// - Throws: An error if the packets cannot be formed.
  static func makePackets(
    messageID: Int32,
    operation: Com_Google_Companionprotos_OperationType,
    payload: Data,
    originalSize: UInt32,
    isPayloadEncrypted: Bool,
    recipient: Data,
    maxSize: Int
  ) throws -> [Com_Google_Companionprotos_Packet] {
    let bleDeviceMessage = makeDeviceMessage(
      operation: operation,
      isPayloadEncrypted: isPayloadEncrypted,
      payload: payload,
      originalSize: originalSize,
      recipient: recipient
    )

    let packetPayload: Data
    do {
      packetPayload = try bleDeviceMessage.serializedData()
    } catch {
      // This error shouldn't happen because the device message should be properly formed.
      Self.log.error(
        "Unexpected, unable to serialize BLEDeviceMessage: \(error.localizedDescription)")
      throw MessagePacketFactoryError.cannotFormMessage
    }

    let headerSize = calculateHeaderSize(messageID: messageID, maxSize: maxSize)
    let payloadSize = packetPayload.count

    guard
      let (totalPackets, maxPayloadSize) = try? calculateTotalPackets(
        maxSize: maxSize,
        headerSize: headerSize,
        payloadSize: payloadSize
      )
    else {
      throw MessagePacketFactoryError.payloadTooLarge
    }

    // If there is just one packet, no need to copy a range out of the `packetPayload` since it
    // fits. As an optimization, simply make a `MessagePacket` out of it.
    if totalPackets == 1 {
      return [makePacket(messageID: messageID, payload: packetPayload)]
    }

    var chunks: [Com_Google_Companionprotos_Packet] = []
    var start = 0
    var end = maxPayloadSize

    for i in 1...totalPackets {
      // Note: the cast to `Int32` is safe because the size of totalPackets has been verified to
      // fit.
      chunks.append(
        makePacket(
          messageID: messageID,
          payload: packetPayload.subdata(in: start..<end),
          packetNumber: UInt32(i),
          totalPackets: Int32(totalPackets)
        ))

      start = end
      end = min(start + maxPayloadSize, payloadSize)
    }

    return chunks
  }

  /// Calculates the total packets required to fit a payload of the given size with the given max
  /// size.
  ///
  /// - Throws: An error if the payload is too large to be encoded.
  static func calculateTotalPackets(
    maxSize: Int,
    headerSize: Int,
    payloadSize: Int
  ) throws -> (totalPackets: Int32, maxPayloadSize: Int) {
    var totalPackets = 0

    // Loop through all possible encoded byte values for the total packet size. The packet size is
    // an `Int32`, and thus, changes size depending on its value. Due to this, a max payload size
    // cannot be calculated and used to divide the payload to obtain total packets. The max
    // payload size will change depending on the size of total packets since larger total packet
    // sizes increases its encoding bytes.
    for totalPacketsBytes in 1...Varint.maxInt32EncodingBytes {
      let totalPacketsEncodingBytes = totalPacketsBytes + fieldNumberEncodingSize
      let maxPayloadSize = maxSize - headerSize - totalPacketsEncodingBytes

      guard maxPayloadSize > 0 else {
        throw MessagePacketFactoryError.payloadTooLarge
      }

      // Calculate the resulting total packets assuming that the size only takes up the given
      // amount of bytes.
      totalPackets = Int(ceil(Double(payloadSize) / Double(maxPayloadSize)))

      guard totalPackets <= Int32.max else {
        throw MessagePacketFactoryError.payloadTooLarge
      }

      // Check that the actual encoding size matches the assumption. The `Int32` cast is safe here
      // due to the `guard` check above.
      if Varint.encodedSize(of: Int32(totalPackets)) == totalPacketsBytes {
        return (Int32(totalPackets), maxPayloadSize)
      }
    }

    // It shouldn't be possible to reach here. If it does, that means an `Int32` is not big enough
    // to encode the number of packets.
    Self.log.error(
      """
      The number of packets required is too large for an Int32 to encode. \
      Requires \(totalPackets) packets.
      """
    )

    throw MessagePacketFactoryError.payloadTooLarge
  }

  /// Calculates the size of the header for a packet with the given parameters.
  ///
  /// The size of the header will remain constant across packets that share the same payload and
  /// message ID.
  ///
  /// - Returns: The constant header size.
  static func calculateHeaderSize(
    messageID: Int32,
    maxSize: Int
  ) -> Int {
    let messageIdEncodingSize = Varint.encodedSize(of: messageID) + fieldNumberEncodingSize

    // The size of the payload is encoded as a varint.
    let maxSizeVarintSize =
      maxSize >= Int32.max
      ? Varint.encodedSize(of: Int64(maxSize))
      : Varint.encodedSize(of: Int32(maxSize))

    let maxSizeEncodingSize = fieldNumberEncodingSize + maxSizeVarintSize

    return packetNumberEncodingSize + messageIdEncodingSize + maxSizeEncodingSize
  }

  /// Creates a `BleDeviceMessage` proto with the given data.
  static func makeDeviceMessage(
    operation: Com_Google_Companionprotos_OperationType,
    isPayloadEncrypted: Bool,
    payload: Data,
    originalSize: UInt32,
    recipient: Data
  ) -> Com_Google_Companionprotos_Message {
    var bleDeviceMessage = Com_Google_Companionprotos_Message()

    bleDeviceMessage.operation = operation
    bleDeviceMessage.isPayloadEncrypted = isPayloadEncrypted
    bleDeviceMessage.payload = payload
    bleDeviceMessage.originalSize = originalSize
    bleDeviceMessage.recipient = recipient

    return bleDeviceMessage
  }
}
