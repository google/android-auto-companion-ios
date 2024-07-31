// Copyright 2024 Google LLC
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

// MARK: PropertyListPrimitive

/// Marks property list primitives that can be directly stored in a `PropertyListStore` backed by
/// `UserDefaults`.
///
/// Apple's `UserDefaults` (see https://developer.apple.com/documentation/foundation/userdefaults)
/// stores values that can be represented as a property list. Here we declare those property list
/// primitives that we support and can be composed to allow conversion of other types.
public protocol PropertyListPrimitive {}

// MARK: - PropertyListPrimitive and PropertyListConvertible Conformances

extension Bool: PropertyListPrimitive, PropertyListConvertible {}
extension Int: PropertyListPrimitive, PropertyListConvertible {}
extension Double: PropertyListPrimitive, PropertyListConvertible {}
extension String: PropertyListPrimitive, PropertyListConvertible {}

/// Primitive arrays should be of a unified type.
extension Array: PropertyListPrimitive where Element: PropertyListPrimitive {}

/// Primitive dictionaries can have mixed values because that's typically how they will be used for
/// this use case. `UserDefaults` uses an internal dictionary type that has `String` keys and `Any`
/// values.
extension Dictionary: PropertyListPrimitive where Key == String, Value: Any {}

// MARK: - PropertyListConvertible

/// A type that can be converted to and from a primitive suitable for storing in a `PropertyListStore`.
public protocol PropertyListConvertible {
  associatedtype Primitive: PropertyListPrimitive

  /// Construct the compound type from the primitives.
  init(primitive: Primitive) throws

  /// The primitive that represents this value in storage.
  func makePropertyListPrimitive() -> Primitive
}

/// Primitive conformance to `PropertyListConvertible`.
extension PropertyListConvertible where Self: PropertyListPrimitive {
  /// Construct the compound type from the primitives.
  public init(primitive: Self) throws {
    self = primitive
  }

  /// The primitive that represents this value in storage.
  public func makePropertyListPrimitive() -> Self { self }
}

// MARK: - PropertyListConvertible Conformances

extension Array: PropertyListConvertible where Element: PropertyListConvertible {
  /// Construct the compound type from the primitives.
  public init(primitive: [Element.Primitive]) throws {
    self = try primitive.map { try Element(primitive: $0) }
  }

  /// The primitive that represents this value in storage.
  public func makePropertyListPrimitive() -> [Element.Primitive] {
    map { $0.makePropertyListPrimitive() }
  }
}

extension Set: PropertyListConvertible where Element: PropertyListConvertible {
  /// Construct the compound type from the primitives.
  public init(primitive: [Element.Primitive]) throws {
    let array = try primitive.map { try Element(primitive: $0) }
    self = Set(array)
  }

  /// The primitive that represents this value in storage.
  public func makePropertyListPrimitive() -> [Element.Primitive] {
    map { $0.makePropertyListPrimitive() }
  }
}

// MARK: - PropertyListStoreError

/// Error thrown when the stored value cannot be converted to the requested type.
public enum PropertyListStoreError: Swift.Error, CustomStringConvertible {
  /// The primitive does not match the expected value for conversion.
  case malformedPrimitive(String)

  /// Description of the error.
  public var description: String {
    return switch self {
    case .malformedPrimitive(let reason):
      "Malformed primitive: \(reason)"
    }
  }
}

// MARK: - PropertyListStore

/// Provides for property list storage of compound types.
public protocol PropertyListStore {
  /// Access and set primitive convertible values by key in the store.
  ///
  /// - Parameter key: The key for which to fetch the value.
  subscript<T>(key: String) -> T? where T: PropertyListConvertible { get set }

  /// Access and set a primitive convertible value by key in the store.
  ///
  /// This variant allows for value assignments when it may be inconvenient to infer the return type
  /// in the call. The caller can instead specify the return type as an argument.
  ///
  /// A default implementation is provided.
  ///
  /// - Parameters:
  ///   - key: The key for which to fetch the value.
  ///   - returnType: The type to return.
  subscript<T>(
    key: String,
    returning returnType: T.Type
  ) -> T? where T: PropertyListConvertible { get set }

  /// Access and set a primitive convertible values by key in the store substituting a default value
  /// when the stored value is `nil`.
  ///
  /// A default implementation is provided.
  ///
  /// - Parameters:
  ///   - key: The key for which to fetch the value.
  ///   - defaultValue: The value to return is no corresponding value for the key is stored.
  subscript<T>(
    key: String,
    `default` defaultValue: T
  ) -> T where T: PropertyListConvertible { get set }

  /// Remove the value associated with the specified key.
  ///
  /// - Parameter key: The key for which to remove the value.
  func removeValue(forKey key: String)
}

extension PropertyListStore {
  /// Access and set primitive convertible values by key in the store.
  public subscript<T>(
    key: String,
    returning returnType: T.Type
  ) -> T? where T: PropertyListConvertible {
    get {
      self[key]
    }

    set {
      self[key] = newValue
    }
  }

  /// Access and set primitive convertible values by key in the store substituting a default value
  /// when the stored value is `nil`.
  public subscript<T>(
    key: String,
    `default` defaultValue: T
  ) -> T where T: PropertyListConvertible {
    get {
      self[key, returning: T.self] ?? defaultValue
    }

    set {
      self[key, returning: T.self] = newValue
    }
  }
}
