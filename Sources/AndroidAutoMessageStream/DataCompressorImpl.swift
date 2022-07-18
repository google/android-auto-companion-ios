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
///
/// Currently we support ZLIB (both raw and annotated), but it may support more algorithms in the
/// future as needed.
///
/// See: https://developer.apple.com/documentation/accelerate/compressing_and_decompressing_data_with_buffer_compression
///
struct DataCompressorImpl: DataCompressor {
  /// `DataCompressor` using the ZLIB compression algorithm for raw compressed bytes plus
  /// annotated with a header and checksum.
  static let zlib = DataCompressorImpl(algorithm: COMPRESSION_ZLIB, annotator: ZlibAnnotator())

  /// `DataCompressor` using the ZLIB compression algorithm for raw compressed bytes only.
  static let zlibRaw = DataCompressorImpl(algorithm: COMPRESSION_ZLIB, annotator: nil)

  /// The compression algorithm to use for the compression and extraction.
  private let algorithm: compression_algorithm

  /// Optional annotator for annotating the raw compressed data (e.g. adding a header, checksum).
  private let annotator: DataAnnotator?

  /// Initialize with the specified algorithm.
  ///
  /// - Parameter algorithm: Compression algorithm to use.
  /// - Parameter annotator: Optional annotator for annotating the raw compressed data.
  private init(algorithm: compression_algorithm, annotator: DataAnnotator?) {
    self.algorithm = algorithm
    self.annotator = annotator
  }

  /// Attempt to compress the input using the ZLIB compression.
  ///
  /// - Parameter inputData: The data to compress.
  /// - Returns: The compressed data.
  /// - Throws: If the compression fails.
  func compress(_ inputData: Data) throws -> Data {
    // Need more than a byte to even consider for compression.
    guard inputData.count > 1 else {
      throw DataCompressorError.minDataSize(inputData.count)
    }

    var inputBuffer = [UInt8](inputData)
    // The output size should be strictly less than the input size otherwise we don't want it.
    let outputBufferSize = inputBuffer.count - 1
    let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: outputBufferSize)

    let compressedSize = compression_encode_buffer(
      outputBuffer,
      outputBufferSize,
      &inputBuffer,
      inputBuffer.count,
      nil,
      algorithm
    )

    if compressedSize == 0 {
      throw DataCompressorError.failed
    }

    var compressedData = NSData(bytesNoCopy: outputBuffer, length: compressedSize) as Data
    if let annotator = annotator {
      annotator.annotate(compressed: &compressedData, input: inputData)
    }
    return compressedData
  }

  /// Attempt to decompress the input using the ZLIB algorithm.
  ///
  /// - Parameters:
  ///   - inputData: The data to decompress.
  ///   - originalSize: The size (must be positive) of the original uncompressed data.
  /// - Returns: The decompressed data.
  /// - Throws: If the decompression fails.
  func decompress(_ inputData: Data, originalSize: Int) throws -> Data {
    var rawInput = inputData
    if let annotator = annotator {
      annotator.removeAnnotationFrom(&rawInput)
    }

    guard originalSize > 0 else {
      throw DataCompressorError.invalidOriginalSize(originalSize)
    }

    let inputBuffer = [UInt8](rawInput)
    let outputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: originalSize)

    let outputSize = compression_decode_buffer(
      outputBuffer,
      originalSize,
      inputBuffer,
      inputBuffer.count,
      nil,
      algorithm
    )

    guard outputSize > 0 else {
      throw DataCompressorError.failed
    }

    guard outputSize == originalSize else {
      throw DataCompressorError.outputSizeMismatch(originalSize, outputSize)
    }

    return NSData(bytesNoCopy: outputBuffer, length: outputSize) as Data
  }
}

/// Some algorithms (e.g. ZLIB) have optional annotations for the compressed data.
private protocol DataAnnotator {
  /// Annotate the compressed data.
  func annotate(compressed: inout Data, input: Data)

  /// Remove the annotation from the compressed data.
  func removeAnnotationFrom(_ compressed: inout Data)
}

/// Extension for ZLIB constants and operations.
extension DataCompressorImpl {
  private struct ZlibAnnotator: DataAnnotator {
    /// Header for the zlib annotated compressed data.
    ///
    /// ZLIB Level 5 (see the referenced links).
    ///
    /// See https://developer.apple.com/documentation/compression/compression_zlib
    /// See https://stackoverflow.com/questions/9050260/what-does-a-zlib-header-look-like
    private static let header: [UInt8] = [0x78, 0x5E]

    /// Modulus used in computing the checksum as per: https://tools.ietf.org/html/rfc1950
    private static let adlerModulus: UInt32 = 65521

    /// The Adler checksum consists of two 16-bit integers.
    private static let adlerChecksumSize = 2 * MemoryLayout<UInt16>.size

    /// Annotate the compressed data with the ZLIB header and the checksum based on the
    /// uncompressed input.
    func annotate(compressed: inout Data, input: Data) {
      prependWithHeader(&compressed)
      appendChecksum(to: &compressed, input: input)
    }

    /// Remove the ZLIB header and checksum from the compressed data.
    ///
    /// - Parameter compressed: The annotated compressed data.
    /// - Returns: The raw compressed data.
    func removeAnnotationFrom(_ compressed: inout Data) {
      // Strip the header and the two 16 bit checksum.
      compressed = compressed.dropFirst(Self.header.count).dropLast(Self.adlerChecksumSize)
    }

    /// Prepend the header (for ZLIB) since iOS only deals with raw compressed data.
    private func prependWithHeader(_ compressed: inout Data) {
      compressed = Data(Self.header) + compressed
    }

    /// Append the Adler-32 checksum of the input to the compressed data since iOS only deals
    /// with raw compressed data.
    ///
    /// See the checksum spec: https://tools.ietf.org/html/rfc1950
    ///
    /// The checksum is composed of two sums. The first sum is of all the bytes modulo 65521. The
    /// second sum is the sum of the partial first sums modulo 65521.
    private func appendChecksum(to compressed: inout Data, input: Data) {
      // Do the sums using 32 bits to avoid overflow.
      var sumA: UInt32 = 1
      var sumB: UInt32 = 0

      for byte in input {
        sumA = (sumA + UInt32(byte)) % Self.adlerModulus
        sumB = (sumA + sumB) % Self.adlerModulus
      }

      // From the referenced spec, the byte order needs to be big-endian.
      var sumA16 = UInt16(sumA).bigEndian
      var sumB16 = UInt16(sumB).bigEndian
      compressed +=
        Data(bytes: &sumB16, count: MemoryLayout.size(ofValue: sumB16))
        + Data(bytes: &sumA16, count: MemoryLayout.size(ofValue: sumA16))
    }
  }
}
