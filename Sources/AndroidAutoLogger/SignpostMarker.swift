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

/// A signpost marker with a named signpost and an event role.
@available(macOS 10.15, *)
public struct SignpostMarker {
  /// Name of the signpost.
  public let name: StaticString

  /// Role for the marker.
  public let role: Role

  /// Create a signpost marker with the `event` role.
  ///
  /// - Parameter name: Name of the signpost.
  public init(_ name: StaticString) {
    self.init(name, role: .event)
  }

  /// Internal initializer to create a signpost marker.
  ///
  /// - Parameters:
  ///   - name: Name of the signpost.
  ///   - role: Role for the marker.
  fileprivate init(_ name: StaticString, role: Role) {
    self.name = name
    self.role = role
  }
}

/// Signpost for beginning and end markers.
@available(macOS 10.15, *)
public struct SignpostDuration {
  /// Name of the signpost.
  public let name: StaticString

  /// Signpost marker for the beginning.
  public var begin: SignpostMarker { SignpostMarker(name, role: .begin) }

  /// Signpost marker for the end.
  public var end: SignpostMarker { SignpostMarker(name, role: .end) }

  /// Create a signpost with beginning and end markers.
  ///
  /// - Parameter name: Name of the signpost.
  public init(_ name: StaticString) {
    self.name = name
  }
}

// MARK: - SignpostMetrics Role

@available(macOS 10.15, *)
extension SignpostMarker {
  /// Role identifying whether the signpost is a solitary event or bracketing some action.
  ///
  /// Implemented so it can referenced on systems prior to the introduction of `OSSignpostType`.
  public enum Role {
    case event, begin, end
  }
}
