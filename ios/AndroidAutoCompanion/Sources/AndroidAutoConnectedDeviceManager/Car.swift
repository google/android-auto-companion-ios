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

/// Stateless information about a car.
///
/// The `id` is the unique identifier for the car. All additional information is cached from the
/// time of association; it is possible that a property like the name of the device has, in reality,
/// changed without this saved state knowing about it.
public struct Car {
  public let id: String
  public let name: String?

  /// Creates an associated car with the given properties.
  ///
  /// - Parameters:
  ///   - id: The stream that is handling writing.
  ///   - name: The human-readable name of the device.
  public init(id: String, name: String?) {
    self.id = id
    self.name = name
  }
}

extension Car: Hashable {
  public static func == (lhs: Car, rhs: Car) -> Bool {
    return lhs.id == rhs.id
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - Logging Support
extension Car {
  public var logName: String { name ?? "no name" }
}
