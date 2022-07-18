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

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for Data+Extensions.
@available(watchOS 6.0, *)
class DataExtensionsTest: XCTestCase {
  func testDataFromValidHexString_notNil() {
    XCTAssertNotNil(Data(hex: "2AF8"))
    XCTAssertNotNil(Data(hex: "2af8"))
  }

  func testDataFromInvalidHexString_nil() {
    XCTAssertNil(Data(hex: "xyz"))
  }

  func testOddHexDigitCountValid() {
    XCTAssertNotNil(Data(hex: "1"))
    XCTAssertNotNil(Data(hex: "1A2"))
    XCTAssertNotNil(Data(hex: "1A2B3"))
    XCTAssertNotNil(Data(hex: "1A2B3C4"))
  }

  func testEvenHexDigitCountValid() {
    XCTAssertNotNil(Data(hex: "1A"))
    XCTAssertNotNil(Data(hex: "1A2B"))
    XCTAssertNotNil(Data(hex: "1A2B3C"))
    XCTAssertNotNil(Data(hex: "1A2B3C4D"))
  }

  // The hex representation should always be two digits per byte.
  func testRecoverHexStringFromData() {
    XCTAssertEqual(Data(hex: "0")!.hex, "00")
    XCTAssertEqual(Data(hex: "1")!.hex, "01")
    XCTAssertEqual(Data(hex: "A1")!.hex, "A1")
    XCTAssertEqual(Data(hex: "A1B")!.hex, "0A1B")
    XCTAssertEqual(Data(hex: "A100")!.hex, "A100")
    XCTAssertEqual(Data(hex: "A1B2")!.hex, "A1B2")
    XCTAssertEqual(Data(hex: "A1B2C")!.hex, "0A1B2C")
    XCTAssertEqual(Data(hex: "A1B2C3")!.hex, "A1B2C3")
  }
}
