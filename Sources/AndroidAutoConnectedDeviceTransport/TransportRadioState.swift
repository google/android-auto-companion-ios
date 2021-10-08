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

/// Tracks the state of the transport's radio.
public enum TransportRadioState: CustomStringConvertible, Equatable {
  case poweredOn, poweredOff, unknown, other

  public var description: String {
    switch self {
    case .poweredOn:
      return "poweredOn"
    case .poweredOff:
      return "poweredOff"
    case .unknown:
      return "unknown"
    case .other:
      return "other"
    }
  }

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
    self == .other
  }
}
