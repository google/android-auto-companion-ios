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

import XCTest
import AndroidAutoCompanionProtos

@testable import AndroidAutoMessageStream

private typealias Message = Com_Google_Companionprotos_Message
private typealias OperationType = Com_Google_Companionprotos_OperationType

/// Unit tests for `MessagePacketFactory`.
class MessagePacketFactoryTest: XCTestCase {
  // MARK: - Header size tests.

  func testCalculateHeaderSize() {
    // 1 byte to encode the ID, 1 byte for the field number.
    let messageID: Int32 = 1
    let messageIDEncodingSize = 2

    // 1 byte for the payload size, 1 byte for the field number.
    let maxSize = 2
    let maxSizeEncodingSize = 2

    // Packet number if a fixed32, so 4 bytes + 1 byte for field number.
    let packetNumberEncodingSize = 5

    let expectedHeaderSize =
      messageIDEncodingSize + maxSizeEncodingSize
      + packetNumberEncodingSize

    XCTAssertEqual(
      MessagePacketFactory.calculateHeaderSize(
        messageID: messageID,
        maxSize: maxSize
      ), expectedHeaderSize)
  }

  // MARK: - calculateTotalPackets tests

  func testCalculateTotalPackets_throwsErrorIfPacketTooLarge() {
    let maxSize = 50
    let headerSize = 10

    // Too many packets will be required to split a payload of this size.
    let payloadSize = Int(exactly: Int64.max)!

    XCTAssertThrowsError(
      try MessagePacketFactory.calculateTotalPackets(
        maxSize: maxSize,
        headerSize: headerSize,
        payloadSize: payloadSize
      )
    ) { error in
      XCTAssertEqual(error as! MessagePacketFactoryError, .payloadTooLarge)
    }
  }

  func testCalculateTotalPackets_withVarintSize1_returnsCorrectPackets() {
    let maxSize = 50
    let headerSize = 10
    let payloadSize = 100

    // This leaves us 40 bytes to use for the payload and its encoding size. Assuming a varint of
    // size 1 means it takes 2 bytes to encode its value. This leaves 38 bytes for the payload.
    // ceil(payloadSize/38) gives the total packets.
    let expectedTotalPackets: Int32 = 3

    assertCalculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize,
      expectedTotalPackets: expectedTotalPackets
    )
  }

  func testCalculateTotalPackets_withVarintSize2_returnsCorrectPackets() {
    let maxSize = 50
    let headerSize = 10
    let payloadSize = 6000

    // This leaves us 40 bytes to use for the payload and its encoding size. Assuming a varint of
    // size 2 means it takes 3 bytes to encode its value. This leaves 37 bytes for the payload.
    // ceil(payloadSize/37) gives the total packets.
    let expectedTotalPackets: Int32 = 163

    assertCalculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize,
      expectedTotalPackets: expectedTotalPackets
    )
  }

  func testCalculateTotalPackets_withVarintSize3_returnsCorrectPackets() {
    let maxSize = 50
    let headerSize = 10
    let payloadSize = 1_000_000

    // This leaves us 40 bytes to use for the payload and its encoding size. Assuming a varint of
    // size 3 means it takes 4 bytes to encode its value. This leaves 36 bytes for the payload.
    // ceil(payloadSize/36) gives the total packets.
    let expectedTotalPackets: Int32 = 27778

    assertCalculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize,
      expectedTotalPackets: expectedTotalPackets
    )
  }

  func testCalculateTotalPackets_withVarintSize4_returnsCorrectPackets() {
    let maxSize = 50
    let headerSize = 10
    let payloadSize = 178_400_320

    // This leaves us 40 bytes to use for the payload and its encoding size. Assuming a varint of
    // size 4 means it takes 5 bytes to encode its value. This leaves 35 bytes for the payload.
    // ceil(payloadSize/35) gives the total packets.
    let expectedTotalPackets: Int32 = 5_097_152

    assertCalculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize,
      expectedTotalPackets: expectedTotalPackets
    )
  }

  func testCalculateTotalPackets_withVarintSize5_returnsCorrectPackets() {
    let maxSize = 50
    let headerSize = 10
    let payloadSize = 10_000_000_000

    // This leaves us 40 bytes to use for the payload and its encoding size. Assuming a varint of
    // size 5 means it takes 6 bytes to encode its value. This leaves 34 bytes for the payload.
    // ceil(payloadSize/34) gives the total packets.
    let expectedTotalPackets: Int32 = 294_117_648

    assertCalculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize,
      expectedTotalPackets: expectedTotalPackets
    )
  }

  // MARK: makePackets tests

  func testMakePackets_correctlyChunksPayload() {
    let payload = makePayload(length: 10000)

    let packets = try! MessagePacketFactory.makePackets(
      messageID: 1,
      operation: OperationType.clientMessage,
      payload: payload,
      originalSize: 0,
      isPayloadEncrypted: true,
      recipient: Data("id".utf8),
      maxSize: 50
    )

    var reconstructedPayload = Data()

    // Combine together all the payloads within the MessagePackets.
    for packet in packets {
      reconstructedPayload.append(packet.payload)
    }

    let deviceMessage = try! Message(serializedData: reconstructedPayload)
    XCTAssertEqual(deviceMessage.payload, payload)
  }

  func testMakePackets_createsCorrectNumberOfPackets() {
    let payload = makePayload(length: 10000)
    let recipient = Data("id".utf8)
    let messageID: Int32 = 1
    let maxSize = 50

    let deviceMessage = MessagePacketFactory.makeDeviceMessage(
      operation: OperationType.clientMessage,
      isPayloadEncrypted: true,
      payload: payload,
      originalSize: 0,
      recipient: recipient
    )
    let deviceMessageSize = (try! deviceMessage.serializedData()).count

    let packets = try! MessagePacketFactory.makePackets(
      messageID: messageID,
      operation: OperationType.clientMessage,
      payload: payload,
      originalSize: 0,
      isPayloadEncrypted: true,
      recipient: recipient,
      maxSize: maxSize
    )

    // The header size is made of packet number, message ID and max size = 9. To encode total
    // packets, it requires 3 bytes. Subtracting these two values from the max size of 50 gives
    // this value.
    let expectedPayloadSize = 38

    let expectedPackets = Int(ceil(Double(deviceMessageSize) / Double(expectedPayloadSize)))
    XCTAssertEqual(packets.count, expectedPackets)
  }

  // MARK: - Utility methods

  /// Makes a `Data` object that holds a string of the given length.
  private func makePayload(length: Int) -> Data {
    return Data(String(repeating: "a", count: length).utf8)
  }

  /// Asserts that a call to `calculateTotalPackets` returns with the given expected total packets.
  private func assertCalculateTotalPackets(
    maxSize: Int,
    headerSize: Int,
    payloadSize: Int,
    expectedTotalPackets: Int32
  ) {
    let (totalPackets, _) = try! MessagePacketFactory.calculateTotalPackets(
      maxSize: maxSize,
      headerSize: headerSize,
      payloadSize: payloadSize
    )

    XCTAssertEqual(totalPackets, expectedTotalPackets)
  }
}
