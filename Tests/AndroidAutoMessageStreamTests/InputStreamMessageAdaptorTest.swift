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

/// Unit tests for `InputStreamMessageAdaptor`.
class InputStreamMessageAdaptorTest: XCTestCase {
  private var testAdaptor: InputStreamMessageAdaptor<Packet>!

  override func tearDown() {
    if let testAdaptor = testAdaptor {
      testAdaptor.stopDecoding()
      self.testAdaptor = nil
    }

    super.tearDown()
  }

  func testStartDecodingOpensStream() {
    let inputStream = InputStream(data: Data())
    testAdaptor = InputStreamMessageAdaptor<Packet>(inputStream: inputStream)
    testAdaptor.startDecoding { _ in }

    XCTAssertEqual(inputStream.streamStatus.rawValue, Stream.Status.open.rawValue)
  }

  func testStopDecodingClosesStream() {
    let inputStream = InputStream(data: Data())
    testAdaptor = InputStreamMessageAdaptor<Packet>(inputStream: inputStream)
    testAdaptor.startDecoding { _ in }
    testAdaptor.stopDecoding()

    XCTAssertEqual(inputStream.streamStatus.rawValue, Stream.Status.closed.rawValue)
  }

  func testDecodeSingleSmallPacket() throws {
    var controlPacket = Packet()
    controlPacket.packetNumber = 1

    try assertPacketsDecoded([controlPacket])
  }

  func testDecodeSingleMediumPacketsSmallMaxElementSizeThrows() {
    var controlPacket = Packet()
    controlPacket.packetNumber = 1
    controlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80))

    XCTAssertThrowsError(
      try assertPacketsDecoded([controlPacket], maxElementSize: 50)
    ) { error in
      XCTAssertTrue(error is SerialDecodingAdaptorError)
      if case SerialDecodingAdaptorError.maxElementSizeExceeded(_) = error {
        // This is the expected matching error.
      } else {
        XCTFail("Error \(error) should be maxElementSizeExceeded.")
      }
    }
  }

  func testDecodeTwoSmallPackets() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2

    try assertPacketsDecoded([firstControlPacket, secondControlPacket])
  }

  func testDecodeTwoMediumPackets() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1
    firstControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80))

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2
    secondControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80))

    try assertPacketsDecoded([firstControlPacket, secondControlPacket])
  }

  func testDecodeTwoMediumPacketsSmallBuffer() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1
    firstControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80))

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2
    secondControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80))

    try assertPacketsDecoded([firstControlPacket, secondControlPacket], bufferSize: 10)
  }

  func testDecodeTwoLargePackets() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1
    firstControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80 << 7))

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2
    secondControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80 << 7))

    try assertPacketsDecoded([firstControlPacket, secondControlPacket])
  }

  func testDecodeThreeSmallPackets() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2

    var thirdControlPacket = Packet()
    thirdControlPacket.packetNumber = 3

    try assertPacketsDecoded([firstControlPacket, secondControlPacket, thirdControlPacket])
  }

  func testDecodeThreeMediumPackets() throws {
    var firstControlPacket = Packet()
    firstControlPacket.packetNumber = 1
    firstControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80 << 7))

    var secondControlPacket = Packet()
    secondControlPacket.packetNumber = 2
    secondControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80 << 7))

    var thirdControlPacket = Packet()
    thirdControlPacket.packetNumber = 3
    thirdControlPacket.payload = Data(
      [UInt8](repeating: UInt8.random(in: 0 ..< .max), count: 0x80 << 7))

    try assertPacketsDecoded([firstControlPacket, secondControlPacket, thirdControlPacket])
  }
}

// MARK: - Utilities

extension InputStreamMessageAdaptorTest {
  /// Serialize the control packets using the BinaryDelimeter and create an input stream and
  /// corresponding message stream adaptor to decode packets.
  ///
  /// Assert that decoded packets are equal to the control packets.
  ///
  ///   - bufferSize: Size (byte count) of the buffer for reading from the stream or 0 for default.
  ///   - maxElementSize: Max serialized size (byte count) of an element to read or 0 for default.
  private func assertPacketsDecoded(
    _ controlPackets: [Packet],
    bufferSize: Int = 0,
    maxElementSize: Int = 0
  ) throws {
    let inputStream = try makeInputStreamWithPackets(controlPackets)

    let packetDecodedExpectation = XCTestExpectation(description: "Packet Decoded")
    packetDecodedExpectation.expectedFulfillmentCount = controlPackets.count

    // nil packets may or may not be decoded when the input stream reaches the end.
    packetDecodedExpectation.assertForOverFulfill = false

    switch (bufferSize, maxElementSize) {
    case (0, 0):
      testAdaptor = InputStreamMessageAdaptor<Packet>(inputStream: inputStream)
    case (_, 0):
      testAdaptor = InputStreamMessageAdaptor<Packet>(
        inputStream: inputStream,
        bufferSize: bufferSize
      )
    case (0, _):
      testAdaptor = InputStreamMessageAdaptor<Packet>(
        inputStream: inputStream,
        maxElementSize: maxElementSize
      )
    default:
      testAdaptor = InputStreamMessageAdaptor<Packet>(
        inputStream: inputStream,
        bufferSize: bufferSize,
        maxElementSize: maxElementSize
      )
    }

    var testPackets: [Packet] = []
    var decodingError: Error? = nil
    testAdaptor.startDecoding { result in
      packetDecodedExpectation.fulfill()
      switch result {
      case .success(let testPacket):
        guard let testPacket = testPacket else {
          // `nil` packet could be received if stream ended possibly due to the stream closing.
          switch inputStream.streamStatus.rawValue {
          case Stream.Status.atEnd.rawValue, Stream.Status.closed.rawValue:
            break
          default:
            XCTFail("nil packet for stream status: \(inputStream.streamStatus.rawValue)")
            break
          }
          return
        }
        testPackets.append(testPacket)
      case .failure(let error):
        decodingError = error
      }
    }

    wait(for: [packetDecodedExpectation], timeout: 1.0)
    testAdaptor.stopDecoding()

    if let error = decodingError {
      throw error
    } else {
      XCTAssertEqual(testPackets.count, controlPackets.count)
      XCTAssertEqual(testPackets, controlPackets)
    }
  }

  private func makeInputStreamWithPackets(_ packets: [Packet]) throws -> InputStream {
    let outputStream = OutputStream(toMemory: ())
    outputStream.open()
    for packet in packets {
      try BinaryDelimited.serialize(message: packet, to: outputStream)
    }
    outputStream.close()

    guard
      let data = outputStream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey)
        as? Data
    else {
      XCTFail("No data in output stream.")
      throw NSError(domain: "InputStreamMessageAdaptorTest", code: 1, userInfo: nil)
    }
    return InputStream(data: data)
  }
}
