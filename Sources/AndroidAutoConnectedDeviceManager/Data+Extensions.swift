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

/// Data transformations.
extension Data {
  /// Returns a hexadecimal representation of the `Data` contents.
  var hex: String {
    self.map {
      // Each byte is represented by two hex digits.
      var digitPair = String($0, radix: 16, uppercase: true)
      if digitPair.count == 1 {
        digitPair = "0" + digitPair
      }
      return digitPair
    }.joined()
  }

  /// Initializes from a hexadecimal string.
  ///
  /// The string must contain only a series of valid hexadecimal digits such as "2AF8".
  ///
  /// - Parameter hex: The hexadecimal string.
  /// - Returns: Returns `nil` if the string is not valid hexadecimal.
  init?(hex rawHex: String) {
    if rawHex.isEmpty { return nil }

    // Make sure we have an even number of hex characters (one pair per byte).
    let hex: String
    if rawHex.count.isMultiple(of: 2) {
      hex = rawHex
    } else {
      hex = "0" + rawHex
    }

    // Each byte consists of a pair of hex characters.
    var data = Data(capacity: hex.count / 2)

    var currentIndex = hex.startIndex
    while currentIndex != hex.endIndex {
      // Process two characters at a time.
      let nextIndex = hex.index(currentIndex, offsetBy: 2)
      let bytes = hex[currentIndex..<nextIndex]

      guard let hexValue = UInt8(bytes, radix: 16) else { return nil }
      data.append(hexValue)
      currentIndex = nextIndex
    }

    self = data
  }
}
