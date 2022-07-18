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

/// Formats integers using the specified radix.
///
/// See the Integer Literals subsection in the Swift documentation for details on the swift literal
/// notation for integers:
/// https://docs.swift.org/swift-book/ReferenceManual/LexicalStructure.html#ID414
@available(macOS 10.15, *)
public enum RadixFormat {
  /// Formats as just binary digits.
  case rawBinary

  /// Formats as binary digits prefixed with "0b" following standard Swift literal notation.
  case binary

  /// Formats as just octal digits.
  case rawOctal

  /// Formats as octal digits prefixed with "0o" following standard Swift literal notation.
  case octal

  /// Formats as standard decimal digits.
  case decimal

  /// Formats as just hexadecimal digits.
  case rawHexadecimal

  /// Formats as hexadecimal digits prefixed with "0x" following standard Swift literal notation.
  case hexadecimal

  /// Format the value as noted for the case.
  ///
  /// - Parameter value: Integer to format.
  /// - Returns: A string for the formatted value.
  func format(_ value: Int) -> String {
    switch self {
    case .rawBinary: return String(value, radix: 2)
    case .binary: return "0b" + Self.rawBinary.format(value)
    case .rawOctal: return String(value, radix: 8)
    case .octal: return "0o" + Self.rawOctal.format(value)
    case .decimal: return "\(value)"
    case .rawHexadecimal: return String(value, radix: 16)
    case .hexadecimal: return "0x" + Self.rawHexadecimal.format(value)
    }
  }
}

/// Formats numbers in various decimal notations.
@available(macOS 10.15, *)
public enum DecimalFormat {
  /// Applies no format to the number.
  case none

  /// Fixed number of digits to the right of the decimal.
  case fixed(Int)

  /// Scientific notation with the specified significant figures.
  case scientific(Int)

  /// Placeholder pattern (e.g. "#,##0.0##") following the unicode number format standard.
  ///
  /// See the unicode number format pattern standard:
  /// http://www.unicode.org/reports/tr35/tr35-numbers.html#Number_Format_Patterns
  case pattern(String)

  /// Format the value as noted for the case.
  ///
  /// - Parameter value: Number to format.
  /// - Returns: A string for the formatted value.
  func format(_ value: Double) -> String {
    switch self {
    case .none: return String(describing: value)
    case .fixed(let fractionDigits):
      let formatter = NumberFormatter()
      formatter.numberStyle = .decimal
      formatter.minimumFractionDigits = fractionDigits
      formatter.maximumFractionDigits = fractionDigits
      return formatter.string(from: value as NSNumber) ?? "<unknown>"
    case .scientific(let significantDigits):
      let formatter = NumberFormatter()
      formatter.numberStyle = .scientific
      formatter.usesSignificantDigits = true
      formatter.minimumSignificantDigits = significantDigits
      formatter.maximumSignificantDigits = significantDigits
      return formatter.string(from: value as NSNumber) ?? "<unknown>"
    case .pattern(let pattern):
      let formatter = NumberFormatter()
      // An optional semicolon splits subpatterns for separate positive and negative patterns.
      let subpatterns = pattern.split(separator: ";", maxSplits: 1)
      switch subpatterns.count {  // We should only ever get one or two subpatterns.
      case 1:
        formatter.positiveFormat = pattern
        formatter.negativeFormat = "-" + pattern
      case 2:
        formatter.positiveFormat = String(subpatterns[0])
        formatter.negativeFormat = String(subpatterns[1])
      default:  // We shouldn't ever get here.
        return "<error>"
      }
      return formatter.string(from: value as NSNumber) ?? "<unknown>"
    }
  }
}

// MARK: - String Interpolation Extensions

@available(macOS 10.15, *)
extension String.StringInterpolation {
  /// Append the string interpolation of the value using the specified radix format.
  ///
  /// - Parameters:
  ///   - value: Integer to format.
  ///   - radix: Radix format to perform the value formatting.
  public mutating func appendInterpolation(_ value: Int, radix: RadixFormat) {
    let formattedValue = radix.format(value)
    appendLiteral(formattedValue)
  }

  /// Append the string interpolation of the value using the specified format.
  ///
  /// - Parameters:
  ///   - value: Number to format.
  ///   - format: The format to perform the value formatting.
  public mutating func appendInterpolation(_ value: Double, format: DecimalFormat) {
    let formattedValue = format.format(value)
    appendLiteral(formattedValue)
  }

  /// Append the string interpolation of the value using the specified format pattern.
  ///
  /// - Parameters:
  ///   - value: Number to format.
  ///   - pattern: The pattern of the format to perform the value formatting.
  public mutating func appendInterpolation(_ value: Double, pattern: String) {
    let formattedValue = DecimalFormat.pattern(pattern).format(value)
    appendLiteral(formattedValue)
  }
}
