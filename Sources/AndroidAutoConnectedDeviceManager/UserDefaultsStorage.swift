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

/// Convenience abstraction over `UserDefaults` that ensures all values set through this class
/// will have keys namespaced to this library.
class UserDefaultsStorage {
  private static let keyPrefix = "com.google.trustagent."

  public static let shared = UserDefaultsStorage()

  private init() {}

  /// Sets the given boolean value for the given key.
  ///
  /// - Parameters:
  ///   - value: The boolean value to store.
  ///   - key: The key to associate with the value.
  public func set(_ value: Bool, forKey key: String) {
    UserDefaults.standard.set(value, forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  /// Sets the given string value for the given key.
  ///
  /// - Parameters:
  ///   - value: The string value to store.
  ///   - key: The key to associate with the value.
  public func set(_ value: String, forKey key: String) {
    UserDefaults.standard.set(value, forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  /// Sets the given object value for the given key.
  ///
  /// - Parameters:
  ///   - value: The object value to store.
  ///   - key: The key to associate with the value.
  public func set(_ value: Any, forKey key: String) {
    UserDefaults.standard.set(value, forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  /// Returns a boolean value that has been associated with the given key. If no value has been
  /// set for the key, then `false` is returned.
  ///
  /// - Returns: The boolean value associated with the given key or `false` if none exists.
  public func bool(forKey key: String) -> Bool {
    return UserDefaults.standard.bool(forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  /// Returns a string value that has been associated with the given key. If no value has been
  /// set for the key, then nil is returned.
  ///
  /// - Returns: The string value associated with the given key or nil if none exists.
  public func string(forKey key: String) -> String? {
    return UserDefaults.standard.string(forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  /// Returns a data value that has been associated with the given key.
  ///
  /// - Returns: The string value associated with the given key or nil if none exists.
  public func data(forKey key: String) -> Data? {
    return UserDefaults.standard.object(forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
      as? Data
  }

  /// Registers the contents of the specified dictionary as default values.
  ///
  /// - Parameter registrationDictionary: The dictionary of keys and values to register.
  public func register(defaults registrationDictionary: [String: Any]) {
    var prefixedDictionary: [String: Any] = [:]

    registrationDictionary.forEach { key, value in
      prefixedDictionary[UserDefaultsStorage.createPrefixedKey(fromKey: key)] = value
    }

    UserDefaults.standard.register(defaults: prefixedDictionary)
  }

  /// Removes all entries from `UserDefaults` that were set through this class.
  public func clearAll() {
    let userDefaults = UserDefaults.standard

    // Only remove keys that start with this class' unique prefix.
    userDefaults.dictionaryRepresentation().keys.forEach { key in
      if key.starts(with: UserDefaultsStorage.keyPrefix) {
        userDefaults.removeObject(forKey: key)
      }
    }
  }

  /// Removes entry from `UserDefaults` with a specific key.
  public func remove(forKey key: String) {
    UserDefaults.standard.removeObject(forKey: UserDefaultsStorage.createPrefixedKey(fromKey: key))
  }

  private static func createPrefixedKey(fromKey key: String) -> String {
    return "\(keyPrefix)\(key)"
  }
}
