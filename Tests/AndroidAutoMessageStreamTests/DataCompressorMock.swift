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

import Foundation

@testable import AndroidAutoMessageStream

/// Mock for compression/decompression operations.
class DataCompressorMock: DataCompressor {
  // MARK: - Method call checks
  public var compressCalled = false
  public var decompressCalled = false

  /// Rearrange the data in a recoverable way to simulate compression.
  ///
  /// - Parameter inputData: The data to compress.
  /// - Returns: The compressed data.
  func compress(_ inputData: Data) -> Data {
    compressCalled = true

    guard inputData.count > 1 else { return inputData }

    // Cycle the first datum to the end to simulate lossless 'compression'.
    return inputData[1...] + [inputData.first!]
  }

  /// Recover the 'compressed' data by reversing the compression rearrangement.
  ///
  /// - Parameters:
  ///   - inputData: The data to decompress.
  ///   - originalSize: The size of the original uncompressed data.
  /// - Returns: The decompressed data.
  func decompress(_ inputData: Data, originalSize: Int) -> Data {
    decompressCalled = true

    guard inputData.count > 1 else { return inputData }

    // Recover 'uncompressed' data by cycling the last datum to the head.
    var output = inputData.dropLast()
    output.insert(inputData.last!, at: 0)
    return output
  }
}
