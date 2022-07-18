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

import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for AnyOutOfBandTokenProvider.
class AccessoryOutOfBandTokenProviderTest: XCTestCase {
  private static let accessoryProtocolsKey = "UISupportedExternalAccessoryProtocols"

  func testAccessoryProtocolIdentifierLoadsFromInfo() throws {
    let identifier = "com.google.xyz.oob-association"
    let info: [String: Any] = [
      "control1": "ignore this",
      Self.accessoryProtocolsKey: [
        "com.google.first", identifier, "com.google.last",
      ],
      "control2": 12345,
    ]

    let accessoryProtocol = try XCTUnwrap(
      AccessoryOutOfBandTokenProvider.AccessoryProtocol(info: info),
      "AccessoryProtocol nil even though info contains a valid protocol string."
    )

    XCTAssertEqual(accessoryProtocol.identifier, identifier)
  }

  func testAccessoryProtocolNilWhenMissingFromInfo() {
    let info: [String: Any] = [
      "control1": "ignore this",
      Self.accessoryProtocolsKey: [
        "com.google.first", "com.google.middle", "com.google.last",
      ],
      "control2": 12345,
    ]

    XCTAssertNil(AccessoryOutOfBandTokenProvider.AccessoryProtocol(info: info))
  }
}
