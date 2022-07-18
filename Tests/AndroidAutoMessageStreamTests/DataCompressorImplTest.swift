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

@testable import AndroidAutoMessageStream

/// Unit tests for `DataCompressorImpl`.
class DataCompressorImplTest: XCTestCase {
  func testRawZlib_Compresses() {
    let rawData = repeatingData(count: 1000)
    let compressor = DataCompressorImpl.zlibRaw
    guard let compressedData = try? compressor.compress(rawData) else {
      XCTFail("Data failed to compress.")
      return
    }

    XCTAssertLessThan(compressedData.count, rawData.count)
  }

  func testRawZlib_CompressedMatchesExpected() {
    let test = Data("AAAA AAAA AAAA AAAA".utf8)
    let compressor = DataCompressorImpl.zlibRaw
    guard let compressed = try? compressor.compress(test) else {
      XCTFail("Data failed to compress.")
      return
    }

    let compressedHex = compressed.hexadecimalDescription

    XCTAssertEqual(compressedHex, "73 74 74 74 54 70 44 21 0")
  }

  func testRawZlib_DecompressRecoversOriginal() {
    let rawData = repeatingData(count: 1000)
    let compressor = DataCompressorImpl.zlibRaw
    guard let compressedData = try? compressor.compress(rawData) else {
      XCTFail("Data failed to compress.")
      return
    }

    guard
      let decompressedData =
        try? compressor.decompress(
          compressedData,
          originalSize: 1000)
    else {
      XCTFail("Data failed to decompress.")
      return
    }

    XCTAssertEqual(decompressedData.count, rawData.count)
    XCTAssertEqual(decompressedData, rawData)
  }

  func testAnnotatedZlib_CompressedMatchesExpected() {
    let test = Data("AAAA AAAA AAAA AAAA".utf8)
    let compressor = DataCompressorImpl.zlib
    guard let compressed = try? compressor.compress(test) else {
      XCTFail("Data failed to compress.")
      return
    }

    let compressedHex = compressed.hexadecimalDescription

    XCTAssertEqual(compressedHex, "78 5E 73 74 74 74 54 70 44 21 0 2C 73 4 71")
  }

  func testAnnotatedZlib_DecompressRecoversOriginal() {
    let rawData = repeatingData(count: 1000)
    let compressor = DataCompressorImpl.zlib
    guard let compressedData = try? compressor.compress(rawData) else {
      XCTFail("Data failed to compress.")
      return
    }

    guard
      let decompressedData =
        try? compressor.decompress(
          compressedData,
          originalSize: rawData.count)
    else {
      XCTFail("Data failed to decompress.")
      return
    }

    XCTAssertEqual(decompressedData.count, rawData.count)
    XCTAssertEqual(decompressedData, rawData)
  }

  // MARK: - Utilities

  /// Generate repeating data which should compress very well.
  private func repeatingData(count: Int) -> Data {
    let array = [UInt8](repeating: 12, count: count)
    return Data(array)
  }
}
