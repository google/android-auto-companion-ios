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

import AndroidAutoLogger
import Foundation

/// A class that stores secure session information in the keychain.
class KeychainSecureSessionManager: NSObject {
  private static let log = Logger(for: KeychainSecureSessionManager.self)

  private func secureSessionKey(for identifier: String) -> Data {
    return Data("com.google.ios.aae.trustagentclient.secureSessionKey.\(identifier)".utf8)
  }

  /// The query to retrieve a saved secure connection for a car.
  ///
  /// This query does not consider the access mode because it is not considered for
  /// uniqueness. However, storing the secure session will have access mode set.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func secureSessionGetQuery(for identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: secureSessionKey(for: identifier),
      kSecReturnData as String: true,
    ]
  }

  /// The query to store a secure session for a car.
  ///
  /// - Parameters:
  ///   - secureSession: The session to save.
  ///   - identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func secureSessionAddQuery(secureSession: Data, identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: secureSessionKey(for: identifier),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: secureSession,
    ]
  }
}

// MARK: - SecureSessionManager

extension KeychainSecureSessionManager: SecureSessionManager {
  /// The stored secure session for a given car or `nil` if none has been saved.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the secure session of `nil` if there was an error.
  func secureSession(for identifier: String) -> Data? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      secureSessionGetQuery(for: identifier) as CFDictionary,
      &item
    )

    guard status == errSecSuccess else {
      Self.log.error("Unable to secure session; err: \(status)")
      return nil
    }

    return item as? Data
  }

  /// Stores the given `Data` objects as a secure session for a car.
  ///
  /// - Parameters:
  ///   - secureSession: The session to save.
  ///   - identifier: The identifier for the car.
  /// - Returns: `true` if the operation was successful.
  func storeSecureSession(_ secureSession: Data, for identifier: String) -> Bool {
    // Avoid storing duplicate keys by checking if there is already an entry and deleting it.
    clearSecureSession(for: identifier)

    let addQuery = secureSessionAddQuery(secureSession: secureSession, identifier: identifier)
    let status = SecItemAdd(addQuery as CFDictionary, nil)

    guard status == errSecSuccess else {
      Self.log.error("Unable to store secure session; err: \(status)")
      return false
    }

    return true
  }

  /// Clears any stored secure sessions for the given car.
  ///
  /// - Parameter identifier: the identifier of the car.
  func clearSecureSession(for identifier: String) {
    SecItemDelete(secureSessionGetQuery(for: identifier) as CFDictionary)
  }
}
