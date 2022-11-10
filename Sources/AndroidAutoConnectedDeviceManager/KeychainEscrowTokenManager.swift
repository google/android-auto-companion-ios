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

/// A class that handles the process of generating and storing a unique identifier for a trusted
/// device registration session.
class KeychainEscrowTokenManager: NSObject, EscrowTokenManager {
  private static let log = Logger(for: KeychainEscrowTokenManager.self)

  /// Generates an escrow token that can be used to uniquely identify an association session.
  ///
  /// - Returns: A `Data` object containing the escrow token as its value.
  private static func generateToken() -> Data {
    var value = UInt64.random(in: UInt64.min...UInt64.max)
    return Data(bytes: &value, count: MemoryLayout<UInt64>.size)
  }

  private func tokenKey(for identifier: String) -> Data {
    return Data("com.google.ios.aae.trustagentclient.tokenKey.\(identifier)".utf8)
  }

  private func handleKey(for identifier: String) -> Data {
    return Data("com.google.ios.aae.trustagentclient.handleKey.\(identifier)".utf8)
  }

  /// The query to retrieve a stored escrow token for a car.
  ///
  /// This query does not consider the access mode because it is not considered for
  /// uniqueness. However, storing the token will have access mode set.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func tokenGetQuery(for identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tokenKey(for: identifier),
      kSecReturnData as String: true,
    ]
  }

  /// The query to retrieve a stored association handle for a car.
  ///
  /// This query does not consider the access mode because it is not considered for
  /// uniqueness. However, storing the handle will have access mode set.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func handleGetQuery(for identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: handleKey(for: identifier),
      kSecReturnData as String: true,
    ]
  }

  /// The query to add an escrow token for a car.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func tokenAddQuery(token: Data, identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: tokenKey(for: identifier),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: token,
    ]
  }

  /// The query to add an association handle for a car.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: The query dictionary.
  private func handleAddQuery(handle: Data, identifier: String) -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrApplicationTag as String: handleKey(for: identifier),
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
      kSecValueData as String: handle,
    ]
  }

  /// The stored escrow token or `nil` if `generateAndStoreToken` had not been called for
  /// the `identifier`, or there was an error.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the escrow token or `nil` if there was an error.
  func token(for identifier: String) -> Data? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      tokenGetQuery(for: identifier) as CFDictionary,
      &item
    )

    guard status == errSecSuccess else {
      if status == errSecItemNotFound {
        Self.log("No escrow token found.")
      } else {
        Self.log.error("Unable to retrieve generated escrow token; err: \(status)")
      }
      return nil
    }

    return item as? Data
  }

  /// The stored handle or `nil` if `storeHandle` has not been called for the `identifier` or
  /// there was an error during the storage process.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the handle or `nil` if there was an error.
  func handle(for identifier: String) -> Data? {
    var item: CFTypeRef?
    let status = SecItemCopyMatching(
      handleGetQuery(for: identifier) as CFDictionary,
      &item
    )

    guard status == errSecSuccess else {
      Self.log.error("Unable to retrieve association handle; err: \(status)")
      return nil
    }

    return item as? Data
  }

  /// Generates and returns an escrow token that can be used to uniquely identify an association
  /// session.
  ///
  /// The generated token is stored securely and can be retrieved later via the
  /// `retrieveStoredEscrowToken` method.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the escrow token as its value or `nil` if there was an
  ///     error storing the token.
  func generateAndStoreToken(for identifier: String) -> Data? {
    // Avoid storing duplicate keys by checking if there is already an entry and deleting it.
    clearToken(for: identifier)

    let escrowToken = KeychainEscrowTokenManager.generateToken()

    // Save the generated escrow token value into keychain.
    let addQuery = tokenAddQuery(token: escrowToken, identifier: identifier)
    let status = SecItemAdd(addQuery as CFDictionary, nil)

    guard status == errSecSuccess else {
      Self.log.error("Unable to store generated escrow token; err: \(status)")
      return nil
    }

    return escrowToken
  }

  /// Stores the given `Data` object as the association handle that can be used to uniquely identify
  /// an association session.
  ///
  /// The handle is stored securely and can be retrieved later via the
  /// `retrieveStoredAssociationHandle` method.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: `true` if the association handle was successfully stored.
  func storeHandle(_ handle: Data, for identifier: String) -> Bool {
    // Avoid storing duplicate keys by checking if there is already an entry and deleting it.
    clearHandle(for: identifier)

    let addQuery = handleAddQuery(handle: handle, identifier: identifier)
    let status = SecItemAdd(addQuery as CFDictionary, nil)

    guard status == errSecSuccess else {
      Self.log.error("Unable to store association handle; err: \(status)")
      return false
    }

    return true
  }

  /// Clears any stored enrollment handles.
  ///
  /// - Parameter identifier: The identifier of the car.
  func clearToken(for identifier: String) {
    SecItemDelete(tokenGetQuery(for: identifier) as CFDictionary)
  }

  /// Clears any stored association handles.
  ///
  /// - Parameter identifier: The identifier of the car.
  func clearHandle(for identifier: String) {
    SecItemDelete(handleGetQuery(for: identifier) as CFDictionary)
  }
}
