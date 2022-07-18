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

@testable import AndroidAutoLogger

/// Unit tests for `RadixFormat` including string interpolation.

class RadixFormatTest: XCTestCase {
  public func testRawBinaryFormat() {
    XCTAssertEqual(RadixFormat.rawBinary.format(0b100_11010010), "10011010010")
    XCTAssertEqual("\(0b100_11010010, radix: .rawBinary)", "10011010010")
  }

  public func testBinaryFormat() {
    XCTAssertEqual(RadixFormat.binary.format(0b100_11010010), "0b10011010010")
    XCTAssertEqual("\(0b100_11010010, radix: .binary)", "0b10011010010")
  }

  public func testRawOctalFormat() {
    XCTAssertEqual(RadixFormat.rawOctal.format(0o714277), "714277")
    XCTAssertEqual("\(0o714277, radix: .rawOctal)", "714277")
  }

  public func testOctalFormat() {
    XCTAssertEqual(RadixFormat.octal.format(0o714277), "0o714277")
    XCTAssertEqual("\(0o714277, radix: .octal)", "0o714277")
  }

  public func testDecimalFormat() {
    XCTAssertEqual(RadixFormat.decimal.format(54321), "54321")
    XCTAssertEqual("\(54321, radix: .decimal)", "54321")
  }

  public func testRawHexadecimalFormat() {
    XCTAssertEqual(RadixFormat.rawHexadecimal.format(0x4cb2f), "4cb2f")
    XCTAssertEqual("\(0x4cb2f, radix: .rawHexadecimal)", "4cb2f")
  }

  public func testHexadecimalFormat() {
    XCTAssertEqual(RadixFormat.hexadecimal.format(0x4cb2f), "0x4cb2f")
    XCTAssertEqual("\(0x4cb2f, radix: .hexadecimal)", "0x4cb2f")
  }
}

/// Unit tests for `DecimalFormat` including string interpolation.

class DecimalFormatTest: XCTestCase {
  public func testNoneFormat() {
    XCTAssertEqual(DecimalFormat.none.format(12_345.6789123), "12345.6789123")
    XCTAssertEqual("\(12_345.6789123, format: .none)", "12345.6789123")
  }

  public func testFixedFormatPositiveRoundUp() {
    XCTAssertEqual(DecimalFormat.fixed(3).format(12_345.6789123), "12,345.679")
    XCTAssertEqual("\(12_345.6789123, format: .fixed(3))", "12,345.679")
  }

  public func testFixedFormatPositiveRoundDown() {
    XCTAssertEqual(DecimalFormat.fixed(4).format(12_345.6789123), "12,345.6789")
    XCTAssertEqual("\(12_345.6789123, format: .fixed(4))", "12,345.6789")
  }

  public func testFixedFormatNegativeRoundUp() {
    XCTAssertEqual(DecimalFormat.fixed(3).format(-12_345.6789123), "-12,345.679")
    XCTAssertEqual("\(-12_345.6789123, format: .fixed(3))", "-12,345.679")
  }

  public func testFixedFormatNegativeRoundDown() {
    XCTAssertEqual(DecimalFormat.fixed(4).format(-12_345.6789123), "-12,345.6789")
    XCTAssertEqual("\(-12_345.6789123, format: .fixed(4))", "-12,345.6789")
  }

  public func testScientificFormatPositiveRoundUp() {
    XCTAssertEqual(DecimalFormat.scientific(4).format(1.23456789123E4), "1.235E4")
    XCTAssertEqual("\(1.23456789123E4, format: .scientific(4))", "1.235E4")
  }

  public func testScientificFormatPositiveRoundDown() {
    XCTAssertEqual(DecimalFormat.scientific(3).format(5.432106789123E5), "5.43E5")
    XCTAssertEqual("\(5.432106789123E5, format: .scientific(3))", "5.43E5")
  }

  public func testScientificFormatNegativeRoundUp() {
    XCTAssertEqual(DecimalFormat.scientific(4).format(-1.23456789123E4), "-1.235E4")
    XCTAssertEqual("\(-1.23456789123E4, format: .scientific(4))", "-1.235E4")
  }

  public func testScientificFormatNegativeRoundDown() {
    XCTAssertEqual(DecimalFormat.scientific(3).format(-5.432106789123E5), "-5.43E5")
    XCTAssertEqual("\(-5.432106789123E5, format: .scientific(3))", "-5.43E5")
  }

  public func testPatternFormatPositiveRoundUp() {
    XCTAssertEqual(
      DecimalFormat.pattern("#,##0.###").format(12_345.6789123),
      "12,345.679")
    XCTAssertEqual(
      "\(12_345.6789123, pattern: "#,##0.###")",
      "12,345.679")
  }

  public func testPatternFormatPositiveRoundDown() {
    XCTAssertEqual(
      DecimalFormat.pattern("#,##0.#####").format(12_345.6789123),
      "12,345.67891")
    XCTAssertEqual(
      "\(12_345.6789123, pattern: "#,##0.#####")",
      "12,345.67891")
  }

  public func testPatternFormatNegativeRoundUp() {
    XCTAssertEqual(
      DecimalFormat.pattern("#,##0.###").format(-12_345.6789123),
      "-12,345.679")
    XCTAssertEqual(
      "\(-12_345.6789123, pattern: "#,##0.###")",
      "-12,345.679")
  }

  public func testPatternFormatNegativeRoundDown() {
    XCTAssertEqual(
      DecimalFormat.pattern("#,##0.#####").format(-12_345.6789123),
      "-12,345.67891")
    XCTAssertEqual(
      "\(-12_345.6789123, pattern: "#,##0.#####")",
      "-12,345.67891")
  }

  public func testSubPatternFormat() {
    let format = DecimalFormat.pattern("#,##0.00;(#)")

    XCTAssertEqual(format.format(12_345.6), "12,345.60")
    XCTAssertEqual(
      "\(12_345.6, pattern: "#,##0.00;(#)")",
      "12,345.60")

    XCTAssertEqual(format.format(-12_345.6), "(12,345.60)")
    XCTAssertEqual(
      "\(-12_345.6, pattern: "#,##0.00;(#)")",
      "(12,345.60)")
  }
}
