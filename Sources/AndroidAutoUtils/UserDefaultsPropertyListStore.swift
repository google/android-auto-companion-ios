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

private import AndroidAutoLogger
public import Foundation

/// A `PropertyListStore` backed by `UserDefaults`.
public struct UserDefaultsPropertyListStore: PropertyListStore {
  static private let log: Logger = Logger(for: UserDefaultsPropertyListStore.self)
  private let defaults: UserDefaults

  /// Store backed by `UserDefaults.standard`.
  public init() {
    self.init(UserDefaults.standard)
  }

  /// Store backed by the specified `UserDefaults`.
  public init(_ defaults: UserDefaults) {
    self.defaults = defaults
  }

  /// Access and set primitive convertible values by key in the store.
  public subscript<T>(key: String) -> T? where T: PropertyListConvertible {
    get {
      Self.log.debug("Getting value for key: \(key) of type: \(T.self)")
      guard let rawValue = defaults.object(forKey: key) else {
        Self.log.error("Missing value for key: \(key).")
        return nil
      }
      guard let primitive = rawValue as? T.Primitive else {
        Self.log.error(
          """
          Mismatch type of value for key : \(key). Found type: \(type(of: rawValue)) which could \
          not be cast to the requested type: \(T.Primitive.self).
          """)
        return nil
      }
      do {
        return try T.init(primitive: primitive)
      } catch {
        Self.log.error(
          "Error instantiating \(T.self) from \(primitive): \(error.localizedDescription)")
        return nil
      }
    }

    set {
      Self.log.debug("Setting value for key: \(key).")
      defaults.set(newValue?.makePropertyListPrimitive(), forKey: key)
    }
  }

  /// Remove the value associated with the specified key.
  public func removeValue(forKey key: String) {
    Self.log.debug("Remove value for key: \(key)")
    defaults.set(nil, forKey: key)
  }
}
