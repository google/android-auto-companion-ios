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

internal import Testing

@testable internal import AndroidAutoLogger

/// Test formatting of logger output.
@Suite("Logger Formatting Tests")
struct FormattingTests {
  /// Unit tests for `RadixFormat` including string interpolation.
  @Test(
    "Format a number using RadixFormat",
    arguments: [
      (0b100_11010010, "10011010010", RadixFormat.rawBinary),
      (0b100_11010010, "0b10011010010", .binary),
      (0o714277, "714277", .rawOctal),
      (0o714277, "0o714277", .octal),
      (0x1234_5678, "12345678", .rawHexadecimal),
      (0x4cb2f, "0x4cb2f", .hexadecimal),
      (54321, "54321", .decimal),
    ])
  func formatUsingRadixFormat(value: Int, expected: String, formatter: RadixFormat) {
    #expect(expected == formatter.format(value))
    #expect(expected == "\(value, radix: formatter)")
  }

  /// Unit tests for `DecimalFormat` including string interpolation.
  @Test(
    "Format a number using DecimalFormat",
    arguments: [
      (12_345.6789123, "12345.6789123", DecimalFormat.none),
      (12_345.6789123, "12,345.679", .fixed(3)),
      (12_345.6789123, "12,345.6789", .fixed(4)),
      (-12_345.6789123, "-12,345.679", .fixed(3)),
      (-12_345.6789123, "-12,345.6789", .fixed(4)),
      (5.432106789123E5, "5.43E5", .scientific(3)),
      (1.23456789123E4, "1.235E4", .scientific(4)),
      (-5.432106789123E5, "-5.43E5", .scientific(3)),
      (-1.23456789123E4, "-1.235E4", .scientific(4)),
      (12_345.6789123, "12,345.679", .pattern("#,##0.###")),
      (12_345.6789123, "12,345.67891", .pattern("#,##0.#####")),
      (-12_345.6789123, "-12,345.679", .pattern("#,##0.###")),
      (-12_345.6789123, "-12,345.67891", .pattern("#,##0.#####")),
      (12_345.6, "12,345.60", .pattern("#,##0.00;(#)")),
      (-12_345.6, "(12,345.60)", .pattern("#,##0.00;(#)")),
    ])
  func formatUsingDecimalFormat(value: Double, expected: String, formatter: DecimalFormat) {
    #expect(expected == formatter.format(value))
    #expect(expected == "\(value, format: formatter)")
  }
}
