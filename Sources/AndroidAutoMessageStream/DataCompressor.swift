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

import Compression
import Foundation

/// Provide data compression/decompression operations.
protocol DataCompressor {
  /// Compress the specified input data.
  ///
  /// - Parameter inputData: The data to compress.
  /// - Returns: The compressed data.
  /// - Throws: If the compression fails.
  func compress(_ inputData: Data) throws -> Data

  /// Decompress the specified input data.
  ///
  /// - Parameters:
  ///   - inputData: The data to decompress.
  ///   - originalSize: The size of the original uncompressed data.
  /// - Returns: The decompressed data.
  /// - Throws: If the decompression fails.
  func decompress(_ inputData: Data, originalSize: Int) throws -> Data
}

/// Errors that can be thrown during compressor operations.
enum DataCompressorError: Error {
  /// The size of the data doesn't meet the minimum required for compression.
  case minDataSize(Int)

  /// Attempted compression or decompression operation failed.
  case failed

  /// Attempted decompression, but the resulting size didn't match the original size.
  case outputSizeMismatch(Int, Int)

  /// The original size passed for decompression must be strictly positive.
  case invalidOriginalSize(Int)
}

/// Utility extension for visualizing data.
extension Data {
  /// Generate a description in hexadecimal format useful for visualizing the data.
  var hexadecimalDescription: String {
    // String of hexadecimal bytes, e.g. "14 3E 5 AB 79".
    self.map { String($0, radix: 16, uppercase: true) }.joined(separator: " ")
  }
}
