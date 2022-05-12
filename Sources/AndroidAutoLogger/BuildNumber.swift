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

/// Specifies a build number which can be logged.
///
/// The build number is composed of three parts (see go/aae-companion-sdk-versioning):
/// - major: Changes when incompatible API changes are introduced.
/// - minor: Changes with new features that are backwards compatible.
/// - patch: Backwards compatible bug fixes.
///
public struct BuildNumber {
  /// Tracks builds that introduce incompatible API changes.
  public let major: Int

  /// Tracks builds with new features that are backwards compatible.
  public let minor: Int

  /// Tracks builds with backwards compatible bug fixes.
  public let patch: Int

  public init(major: Int, minor: Int, patch: Int) {
    self.major = major
    self.minor = minor
    self.patch = patch
  }
}

// MARK: - CustomStringConvertible Conformance

extension BuildNumber: CustomStringConvertible {
  public var description: String { "\(major).\(minor).\(patch)" }
}

// MARK: - Comparable Conformance

extension BuildNumber: Comparable {
  public static func < (left: Self, right: Self) -> Bool {
    if left.major != right.major {
      return left.major < right.major
    }

    if left.minor != right.minor {
      return left.minor < right.minor
    }

    return left.patch < right.patch
  }
}
