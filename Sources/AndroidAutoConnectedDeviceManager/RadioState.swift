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

internal import Foundation

/// Abstraction of the state of a transport's radio using `CBManagerState` as a reference.
public protocol RadioState: Equatable, Sendable {
  static var poweredOn: Self { get }
  static var poweredOff: Self { get }
  static var unknown: Self { get }

  /// Indicates whether the radio is powered on.
  var isPoweredOn: Bool { get }

  /// Indicates whether the radio is powered off.
  var isPoweredOff: Bool { get }

  /// Indicates whether the radio is in an unknown state.
  var isUnknown: Bool { get }

  /// Indicates whether the radio is in another custom state.
  var isOther: Bool { get }
}

// MARK: - Default implementations
extension RadioState {
  public var isPoweredOn: Bool {
    self == .poweredOn
  }

  public var isPoweredOff: Bool {
    self == .poweredOff
  }

  public var isUnknown: Bool {
    self == .unknown
  }

  public var isOther: Bool {
    !isPoweredOn && !isPoweredOff && !isUnknown
  }
}

// MARK: - Default CustomStringConvertible Conformance
extension RadioState where Self: CustomStringConvertible {
  public var description: String {
    switch self {
    case .poweredOn:
      return "poweredOn"
    case .poweredOff:
      return "poweredOff"
    case .unknown:
      return "unknown"
    default:
      return "other"
    }
  }
}
