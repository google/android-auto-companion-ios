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

import CoreBluetooth
import Foundation

// CBUUID Extensions to prevent data driven crashes.
@available(watchOS 6.0, *)
extension CBUUID {
  /// Valid car ID data size of 128 bits.
  static private let validCarIdDataSizeInBytes = 128 / 8

  /// Initialization error.
  enum InitError: Error {
    /// Attempt to initialize with data of an invalid length in bytes.
    case invalidLength(Int)
  }

  /// Initialize a CBUUID using the specified data representing a car id.
  ///
  /// The usual CBUUID initializer will trap if passed data that doesn't meet certain minimal
  /// requirements. Since we will often be using data that is passed to us, we want to make
  /// sure to check whether the data is valid to avoid crashing. Note that while there are other
  /// criteria for valid UUIDs, CBUUID currently only fails if the byte size is wrong, and the
  /// only valid car id's we support are 128 bits, so we are restricting our validation to just
  /// these constraints.
  ///
  /// See: https://developer.apple.com/documentation/corebluetooth/cbuuid/1518799-init
  ///
  /// - Parameter carId: The car ID data from which to initialized the CBUUID.
  /// - Throws: An `InitError` error if the data is malformed (e.g. length is not 128 bits).
  convenience init(carId: Data) throws {
    guard carId.count == Self.validCarIdDataSizeInBytes else {
      throw InitError.invalidLength(carId.count)
    }

    self.init(data: carId)
  }
}
