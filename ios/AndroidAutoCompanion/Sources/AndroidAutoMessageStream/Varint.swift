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

/// Method related to calculating the size of `Varint`s.
///
/// The methods here are a subset of
/// google3/third_party/swift/swift_protobuf/Sources/SwiftProtobuf/Varint.swift with some local
/// modifications. Any modifications will be pointed out in the method doc.
enum Varint {
  /// The max size in bytes for an `int32` field in a protobuf.
  static let maxInt32EncodingBytes = 5

  /// Computes the number of bytes that would be needed to store a signed 32-bit varint, if it were
  /// treated as an unsigned integer with the same bit pattern.
  ///
  /// This method differs from the google3 version in that it has inlined the logic for
  /// `encodedSize(of:)` that takes an `UInt32` since all proto values should be positive.
  ///
  /// - Parameter value: The number whose varint size should be calculated.
  /// - Returns: The size, in bytes, of the 32-bit varint.
  static func encodedSize(of value: Int32) -> Int {
    let unsigned = UInt32(bitPattern: value)
    if (unsigned & (~0 << 7)) == 0 {
      return 1
    }
    if (unsigned & (~0 << 14)) == 0 {
      return 2
    }
    if (unsigned & (~0 << 21)) == 0 {
      return 3
    }
    if (unsigned & (~0 << 28)) == 0 {
      return 4
    }
    return maxInt32EncodingBytes
  }

  /// Computes the number of bytes that would be needed to store a 64-bit varint.
  ///
  /// - Parameter value: The number whose varint size should be calculated.
  /// - Returns: The size, in bytes, of the 64-bit varint.
  static func encodedSize(of value: Int64) -> Int {
    // Handle two common special cases up front.
    if (value & (~0 << 7)) == 0 {
      return 1
    }
    if value < 0 {
      return 10
    }

    // Divide and conquer the remaining eight cases.
    var value = value
    var n = 2

    if (value & (~0 << 35)) != 0 {
      n += 4
      value >>= 28
    }
    if (value & (~0 << 21)) != 0 {
      n += 2
      value >>= 14
    }
    if (value & (~0 << 14)) != 0 {
      n += 1
    }
    return n
  }
}
