// Copyright 2022 Google LLC
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

import Foundation
import SwiftProtobuf
import XCTest
import AndroidAutoCompanionProtos

@testable import AndroidAutoMessageStream

private typealias Packet = Com_Google_Companionprotos_Packet

/// Unit tests for `Varint`.
class VarintTest: XCTestCase {
  func testSmallVarintSize() throws {
    let data = Data([17])
    let (numRead, size) = try Varint.decodeFirstVarint(from: data)

    XCTAssertEqual(numRead, 1)
    XCTAssertEqual(size, 17)
  }

  func testIncompleteVarintThrowsIncompleteData() throws {
    // If the high bit is set, then subsequent data will be needed to parse the Varint.
    let varintByte: UInt8 = 17 | 0x80
    let data = Data([varintByte])

    XCTAssertThrowsError(try Varint.decodeFirstVarint(from: data)) { error in
      XCTAssertTrue(error is Varint.DecodingError)
      guard let error = error as? Varint.DecodingError else { return }
      XCTAssertEqual(error, .incompleteData)
    }
  }

  func testDecodeFirstVarintSingleByteDataSize() throws {
    try assertFirstVarintDecodingBinaryDelimited(sizeByteCount: 1)
  }

  func testDecodeFirstVarintTwoByteDataSize() throws {
    try assertFirstVarintDecodingBinaryDelimited(sizeByteCount: 2)
  }

  func testDecodeFirstVarintThreeByteDataSize() throws {
    try assertFirstVarintDecodingBinaryDelimited(sizeByteCount: 3)
  }

  func testDecodeFirstVarintFourByteDataSize() throws {
    try assertFirstVarintDecodingBinaryDelimited(sizeByteCount: 4)
  }
}

// MARK: - Utilities

extension VarintTest {
  /// Assert the first Varint decoded correctly measures the data size of the binary delimited data.
  ///
  /// Tests whether `Varint.decodeFirstVarint(from:)` correctly decodes the data size by using it
  /// to measure the data to deserialize and then attempting to deserialize it. Since the `Varint`
  /// itself may be represented in a variable number of bytes, we can call this method to test with
  /// different `Varint` sizes (bytes for Varint itself) and thus spanning different data sizes.
  ///
  /// - Parameter sizeByteCount: Number of bytes encoding the size integer itself.
  /// - Throws: An error if the decoding fails.
  private func assertFirstVarintDecodingBinaryDelimited(sizeByteCount: Int) throws {
    // Create a small packet.
    var controlPacket = Packet()
    controlPacket.packetNumber = 1

    // 1 byte Varint -> Small Packet (no payload).
    // 2 byte Varint -> A Packet with a payload of 0x80.
    // >2 byte Varint -> A Packet with payload of 0x80 shifted by increments of 7.
    if sizeByteCount > 1 {
      let shift = 7 * (sizeByteCount - 2)
      let dataSize = 0x80 << shift
      controlPacket.payload = Data(
        [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: dataSize))
    }

    // Serialize the packet delimited (leading Varint).
    let outputStream = OutputStream(toMemory: ())
    outputStream.open()
    try BinaryDelimited.serialize(message: controlPacket, to: outputStream)
    outputStream.close()

    guard
      let data = outputStream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey)
        as? Data
    else {
      XCTFail("No data in output stream.")
      throw NSError(domain: "InputStreamMessageAdaptorTest", code: 1, userInfo: nil)
    }

    // Decode the Varint.
    let (numRead, dataSize) = try Varint.decodeFirstVarint(from: data)
    XCTAssertEqual(numRead, sizeByteCount)
    let messageData = data[numRead...]
    XCTAssertEqual(dataSize, messageData.count)
    let testPacket = try Packet(serializedData: messageData)
    XCTAssertEqual(controlPacket, testPacket)
  }
}
