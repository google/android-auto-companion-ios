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
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for our `CBUUID` extensions.
@available(watchOS 6.0, *)
class CBUUID_AdditionsTest: XCTestCase {
  // MARK: - Tests

  /// Test that the validating init throws for data of length not equal to 128 bits (16 bytes).
  func testInitWithInvalidDataLength_Throws() {
    XCTAssertThrowsError(try CBUUID(carId: Data("0".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("01".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("bad".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("0123".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("12345".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("01234567".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("0123456789ABCDE".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("0123456789ABCDEF0".utf8)))
    XCTAssertThrowsError(try CBUUID(carId: Data("0123456789ABCDEF0123456789".utf8)))
  }

  /// Test that the validating init doesn't throw for data of length equal to 128 bits (16 bytes).
  func testInitWithValidDataLength_NoThrow() {
    XCTAssertNoThrow(try CBUUID(carId: Data("0123456789ABCDEF".utf8)))
  }
}
