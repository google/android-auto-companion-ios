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

/// Protocol for simple types which can be encoded as metadata.
public protocol LogMetaData: Encodable {}

/// Provide a default implementation for the supported types.
extension LogMetaData {
  func encode(
    to container: inout KeyedEncodingContainer<MetadataCodingKey>,
    forKey key: MetadataCodingKey
  ) throws {
    try container.encode(self, forKey: key)
  }
}

/// Encode the dictionary to the container.
func encodeMetadata(
  _ dictionary: [String: LogMetaData],
  to container: inout KeyedEncodingContainer<MetadataCodingKey>
) throws {
  for (key, value) in dictionary {
    let codingKey = MetadataCodingKey.key(key)
    try value.encode(to: &container, forKey: codingKey)
  }
}

/// Simple coding key that uses a string for a key so we can encode dictionaries.
enum MetadataCodingKey: CodingKey {
  /// The key with the string associated value as the key.
  case key(String)

  public init?(stringValue: String) {
    self = .key(stringValue)
  }

  public var intValue: Int? { nil }
  public init?(intValue: Int) { nil }

  public var stringValue: String {
    switch self {
    case .key(let value): return value
    }
  }
}

// MARK: - Supported Type Conformance

/// Make `Bool` conform to LogMetaData.
extension Bool: LogMetaData {}

/// Make `Int` conform to LogMetaData.
extension Int: LogMetaData {}

/// Make `Double` conform to LogMetaData.
extension Double: LogMetaData {}

/// Make `String` conform to LogMetaData.
extension String: LogMetaData {}

/// Make `Array` conform to LogMetaData.
extension Array: LogMetaData where Element: LogMetaData {}
