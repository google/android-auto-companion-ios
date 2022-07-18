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
import CommonCrypto
import Foundation

/// Car plus the full HMAC of the advertisement salt.
typealias CarAdvertisementMatch = (car: Car, hmac: Data)

/// Protocol for a car authenticator.
protocol CarAuthenticator {
  /// Get the car authenticator for the specified car.
  ///
  ///  - Parameter carId: The car identifier for which to get the authenticator.
  init(carId: String) throws

  /// Generate a random salt with the specified number of bytes plus optional zero padding.
  ///
  /// - Parameter size: The size of the salt in bytes.
  /// - Returns: The generated salt.
  static func randomSalt(size: Int) -> Data

  /// Find a car among those specified which authenticate against the specified advertisement.
  ///
  /// - Parameters:
  ///   - advertisementData: The advertisement data containing the truncated HMAC and salt.
  ///   - cars: The set of cars among which to test for a match.
  /// - Returns: The matching car plus full HMAC or `nil` if none matches.
  static func first(
    among cars: Set<Car>,
    matchingData advertisementData: Data
  ) -> CarAdvertisementMatch?

  /// Compute the HMAC for the specified challenge and compare it with the provided HMAC data.
  ///
  /// - Parameters:
  ///   - challenge: The challenge salt for which to compute the HMAC.
  ///   - hmac: The HMAC data with which to compare with the computed HMAC.
  /// - Returns: `true` if the computed HMAC matches that specified HMAC.
  func isMatch(challenge: Data, hmac: Data) -> Bool
}

/// Responsible for authenticating the car for reconnection.
struct CarAuthenticatorImpl: CarAuthenticator {
  /// Error errors performing key operations (e.g. assigning, generating, storing).
  enum KeyError: Error {
    /// Attempted to assign a key with the wrong number of bytes (should be `keySize` bytes).
    case invalidKeySize(Int)

    /// Failed to find an authenticator for the specified carId.
    case unknownCar(String)

    /// Failed to save the key.
    case saveFailed(OSStatus)

    /// Failed to delete the key.
    case deleteFailed(OSStatus)

    /// Failed to fetch keys.
    case fetchKeysFailed(OSStatus)
  }

  /// Size of the key in bytes (256 bits).
  private static let keySize = 256 / 8

  /// Size of the hash in bytes (SHA256)
  private static let hashSize = Int(CC_SHA256_DIGEST_LENGTH)

  /// Processes the advertisement data.
  enum Advertisement {
    enum PartitionError: Error {
      case invalidLength
    }

    /// Total length of the advertisement data in bytes.
    private static let totalLength = 11

    /// Length of the truncated HMAC in bytes.
    private static let truncatedHMACLength = 3

    /// Length of the zero padding to append to the advertised salt.
    private static let saltZeroPaddingLength = 8

    /// Partition the advertised data into the truncated HMAC and padded salt.
    ///
    /// The advertised data is 11 bytes in total length. The first three bytes is the truncated
    /// HMAC and the remaining eight bytes are the salt. The actual salt used to compute the HMAC
    /// was zero padded with eight additional bytes.
    ///
    /// - Parameter advertisement: The advertisement data.
    /// - Returns: A tuple of the truncated HMAC and padded salt.
    /// - Throws: An error if the advertisement cannot be partitioned as expected.
    static func partition(advertisement: Data) throws -> (truncatedHMAC: Data, paddedSalt: Data) {
      guard advertisement.count == totalLength else {
        throw PartitionError.invalidLength
      }

      let truncatedHMAC = advertisement[0..<truncatedHMACLength]
      let salt = advertisement[truncatedHMACLength...]
      let paddedSaltBytes = Array(salt) + Array(repeating: 0, count: saltZeroPaddingLength)
      let paddedSalt = Data(bytes: paddedSaltBytes, count: paddedSaltBytes.count)

      return (truncatedHMAC: truncatedHMAC, paddedSalt: paddedSalt)
    }

    /// Truncate the specified HMAC according to the advertisement rules.
    ///
    /// - Parameter hmac: This is expected to be a valid HMAC.
    /// - Returns: The truncated HMAC truncated to the first 3 bytes.
    static func truncateHMAC(hmac: Data) -> Data {
      assert(hmac.count == CarAuthenticatorImpl.hashSize, "Invalid HMAC length: \(hmac.count).")
      return hmac[0..<truncatedHMACLength]
    }
  }

  /// The key used for authentication.
  let key: [UInt8]

  /// Generate the data blob for the key.
  var keyData: Data {
    Data(bytes: key, count: key.count)
  }

  /// Convenience initializer randomly generating a key.
  init() {
    let key = (0..<Self.keySize).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
    try! self.init(key: key)
  }

  /// Designated initializer.
  ///
  /// - Parameter key The 256 bit authentication key.
  init(key: [UInt8]) throws {
    guard key.count == Self.keySize else {
      throw KeyError.invalidKeySize(key.count)
    }
    self.key = key
  }

  /// Convenience initializer extracting the key from the specified data.
  ///
  /// - Parameter keyData: Data from which to extract the key.
  init(keyData: Data) throws {
    let key = Array(keyData)
    try self.init(key: key)
  }

  /// Constructs the car authenticator for the specified car.
  ///
  ///  - Parameter carId: The car identifier for which to get the authenticator.
  init(carId: String) throws {
    guard let keyData = KeyChainStorage.fetchKeyData(forIdentifier: carId) else {
      throw KeyError.unknownCar(carId)
    }
    try self.init(keyData: keyData)
  }

  /// Generate a random salt with the specified number of bytes plus optional zero padding.
  ///
  /// - Parameter size: The size of the salt in bytes.
  /// - Returns: The generated salt.
  static func randomSalt(size: Int) -> Data {
    let salt = (0..<size).map { _ in UInt8.random(in: UInt8.min...UInt8.max) }
    return Data(bytes: salt, count: salt.count)
  }

  /// Find a car whose associated key generates a truncated HMAC for the advertised salt
  /// which matches the truncated HMAC in the advertised data.
  ///
  /// It's possible though unlikely that more than one car may match the truncated HMAC, so
  /// the caller will need to further authenticate and possibly disconnect and rescan for a
  /// new advertisement as necessary.
  ///
  /// The advertisement data contains 11 bytes. The first 3 bytes are the truncated HMAC for
  /// the padded salt. The next 8 bytes contain the salt.
  ///
  /// To authenticate the device for a car, we must:
  ///   1) Zero pad the salt to a total of 16 bytes.
  ///   2) Fetch from the keychain, the authentication key that had been saved for the car.
  ///   3) Use the key to generate an HMAC for the padded salt.
  ///   4) Truncate the HMAC to 3 bytes and compare with the advertised truncated HMAC.
  ///
  /// - Parameters:
  ///   - cars: The set of cars among which to test for a match.
  ///   - advertisementData: The advertisement data containing the truncated HMAC and salt.
  /// - Returns: The matching car plus full HMAC or `nil` if none matches.
  static func first(
    among cars: Set<Car>,
    matchingData advertisementData: Data
  ) -> CarAdvertisementMatch? {
    // If we can't partition the advertisement as expected then we don't have a match.
    guard
      let (advertisedTruncatedHMAC, paddedSalt) =
        try? Advertisement.partition(advertisement: advertisementData)
    else {
      return nil
    }

    // Find a car whose key autenticates the advertised truncated HMAC for the advertised salt.
    for car in cars {
      guard let authenticator = try? CarAuthenticatorImpl(carId: car.id) else {
        continue
      }
      let hmac = authenticator.computeHMAC(data: paddedSalt)
      let truncatedHMAC = Advertisement.truncateHMAC(hmac: hmac)
      if truncatedHMAC == advertisedTruncatedHMAC {
        return (car: car, hmac: hmac)
      }
    }

    return nil
  }

  /// Compute the HMAC for the specified challenge and compare it with the provided HMAC data.
  ///
  /// - Parameters:
  ///   - challenge: The challenge salt for which to compute the HMAC.
  ///   - hmac: The HMAC data with which to compare with the computed HMAC.
  /// - Returns: `true` if the computed HMAC matches that specified HMAC.
  func isMatch(challenge: Data, hmac: Data) -> Bool {
    guard hmac.count == Self.hashSize else {
      return false
    }

    let computedHMAC = computeHMAC(data: challenge)

    return computedHMAC == hmac
  }

  /// Compute the authentication code for the specified data using the authenticator's key.
  ///
  /// - Parameter data: The data to hash.
  /// - Returns: The 256 bit SHA authentication code.
  func computeHMAC(data: Data) -> Data {
    let dataBytes = [UInt8](data)
    var mac: [UInt8] = Array.init(repeating: 0, count: Self.hashSize)
    CCHmac(
      CCHmacAlgorithm(kCCHmacAlgSHA256),
      key,
      key.count,
      dataBytes,
      dataBytes.count,
      &mac
    )
    return Data(bytes: mac, count: mac.count)
  }

  /// Save to the keychain, the key for the specified car.
  ///
  /// - Parameter identifier: The car identifier.
  /// - Throws: An error if the key cannot be stored.
  func saveKey(forIdentifier identifier: String) throws {
    try KeyChainStorage.save(keyData: keyData, forIdentifier: identifier)
  }

  /// Remove the key for the specified car.
  ///
  /// - Parameter identifier: The car identifier.
  static func removeKey(forIdentifier identifier: String) throws {
    try KeyChainStorage.removeKey(forIdentifier: identifier)
  }

  /// Storage for saving and recovering authentication data.
  private enum KeyChainStorage {
    static private let log = Logger(for: KeyChainStorage.self)

    /// Label for the key query.
    static private let keyLabel = "com.google.ios.aae.trustagentclient.CarAuthenticatorImpl.key"

    /// Save to the keychain, the key for the specified car.
    ///
    /// - Parameters:
    ///   - keyData: The data of the key to save.
    ///   - identifier: The car identifier.
    /// - Throws: An error if the key cannot be stored.
    static func save(keyData: Data, forIdentifier identifier: String) throws {
      let tag = keyTag(forIdentifier: identifier)
      let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tag,
        kSecAttrLabel as String: keyLabel,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        kSecValueData as String: keyData,
      ]

      let status = SecItemAdd(query as CFDictionary, nil)

      switch status {
      case errSecSuccess: return
      case errSecDuplicateItem:
        let updatedAttributes: [String: Any] = [kSecValueData as String: keyData]
        let updateStatus = SecItemUpdate(query as CFDictionary, updatedAttributes as CFDictionary)
        if updateStatus != errSecSuccess {
          Self.log.error("Unable to update the car authentication key; err: \(status)")
          throw KeyError.saveFailed(status)
        }
      default:
        Self.log.error("Unable to save the car authentication key; err: \(status)")
        throw KeyError.saveFailed(status)
      }
    }

    static func fetchKeyData(forIdentifier identifier: String) -> Data? {
      let tag = keyTag(forIdentifier: identifier)
      let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tag,
        kSecAttrLabel as String: keyLabel,
        kSecMatchLimit as String: kSecMatchLimitOne,
        kSecReturnAttributes as String: false,
        kSecReturnData as String: true,
      ]

      var item: CFTypeRef?
      let _ = SecItemCopyMatching(query as CFDictionary, &item)
      guard let itemData = item as? NSData else {
        return nil
      }
      return itemData as Data
    }

    /// Remove from the keychain, the key for the specified car.
    ///
    /// - Parameter identifier: The car identifier.
    /// - Throws: An error if the key cannot be stored.
    static func removeKey(forIdentifier identifier: String) throws {
      let tag = keyTag(forIdentifier: identifier)
      let query: [String: Any] = [
        kSecClass as String: kSecClassKey,
        kSecAttrApplicationTag as String: tag,
      ]

      let status = SecItemDelete(query as CFDictionary)
      guard status == errSecSuccess else {
        Self.log.error("Failed to delete the car authentication key; err: \(status)")
        throw KeyError.deleteFailed(status)
      }
    }

    static private func keyTag(forIdentifier identifier: String) -> Data {
      return Data("com.google.ios.aae.trustagentclient.CarAuthenticatorImpl.key.\(identifier)".utf8)
    }
  }
}
