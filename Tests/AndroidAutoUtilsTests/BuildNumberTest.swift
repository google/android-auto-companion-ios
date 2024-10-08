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

internal import XCTest

@testable private import AndroidAutoUtils

/// `BuildNumber` unit tests.
class BuildNumberTest: XCTestCase {
  // MARK: - Tests

  /// Test the description.
  func testDescription() {
    let build = BuildNumber(major: 2, minor: 3, patch: 5)

    XCTAssertEqual(build.description, "2.3.5")
  }
}

// MARK: Test Equatable

extension BuildNumberTest {
  func testEquatable() {
    XCTAssertEqual(
      BuildNumber(major: 5, minor: 7, patch: 11),
      BuildNumber(major: 5, minor: 7, patch: 11)
    )

    XCTAssertNotEqual(
      BuildNumber(major: 5, minor: 7, patch: 11),
      BuildNumber(major: 4, minor: 7, patch: 11)
    )

    XCTAssertNotEqual(
      BuildNumber(major: 5, minor: 7, patch: 11),
      BuildNumber(major: 5, minor: 9, patch: 11)
    )

    XCTAssertNotEqual(
      BuildNumber(major: 5, minor: 7, patch: 18),
      BuildNumber(major: 5, minor: 7, patch: 11)
    )
  }
}

// MARK: Test Comparable

extension BuildNumberTest {
  func testComparable() {
    XCTAssertLessThan(
      BuildNumber(major: 2, minor: 7, patch: 11),
      BuildNumber(major: 3, minor: 3, patch: 5)
    )

    XCTAssertLessThan(
      BuildNumber(major: 2, minor: 3, patch: 11),
      BuildNumber(major: 2, minor: 5, patch: 11)
    )

    XCTAssertLessThan(
      BuildNumber(major: 2, minor: 3, patch: 7),
      BuildNumber(major: 2, minor: 3, patch: 12)
    )

    XCTAssertGreaterThan(
      BuildNumber(major: 5, minor: 7, patch: 11),
      BuildNumber(major: 3, minor: 3, patch: 5)
    )

    XCTAssertGreaterThan(
      BuildNumber(major: 2, minor: 7, patch: 11),
      BuildNumber(major: 2, minor: 5, patch: 11)
    )

    XCTAssertGreaterThan(
      BuildNumber(major: 2, minor: 3, patch: 18),
      BuildNumber(major: 2, minor: 3, patch: 12)
    )
  }
}

// MARK: Test PropertyListConvertible

extension BuildNumberTest {
  func testMakePropertyList() throws {
    let test = try BuildNumber(primitive: [2, 3, 5])

    XCTAssertEqual(test.major, 2)
    XCTAssertEqual(test.minor, 3)
    XCTAssertEqual(test.patch, 5)
  }

  func testInstantiateFromPropertyList() {
    let buildNumber = BuildNumber(major: 2, minor: 3, patch: 5)
    let test = buildNumber.makePropertyListPrimitive()

    XCTAssertEqual(test, [2, 3, 5])
  }
}
