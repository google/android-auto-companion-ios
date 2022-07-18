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

/// Protocol configuration for the TrustAgent library.
@available(watchOS 6.0, *)
protocol TrustAgentConfig: AnyObject {

  /// Whether a passcode is required for enrolling and unlocking.
  var isPasscodeRequired: Bool { get set }

  /// Whether unlock history should be stored automatically by the manager.
  ///
  /// This value should be `true` by default.
  var isUnlockHistoryEnabled: Bool { get }

  /// Whether this device is required to be unlocked for unlocking the car.
  func isDeviceUnlockRequired(for car: Car) -> Bool

  /// Set whether this device is required to be unlocked for unlocking the car.
  func setDeviceUnlockRequired(_ isRequired: Bool, for car: Car)

  /// Returns `true` if the current device has all the necessary requirements for a passcode have
  /// been met.
  ///
  /// A value of `true` indicates that trust agent enrollment can proceed.
  func arePasscodeRequirementsMet() -> Bool

  /// Returns `true` if the current device has all the necessary requirements for lock state.
  ///
  /// A value of `true` indicates that trust agent enrollment can proceed
  func areLockStateRequirementsMet(for car: Car) -> Bool

  /// Clear the trust agent configuration for the car.
  func clearConfig(for car: Car)
}

/// A configuration for the trust agent whose storage is backed by `UserDefaults`.
///
/// Due to the usage of `UserDefaults`, each instance of this class will utilize the same storage.
@available(watchOS 6.0, *)
class TrustAgentConfigUserDefaults: TrustAgentConfig {
  #if os(watchOS)
    // we don't currently have a way to enforce this on watch, so for now no requirement
    private static let defaultPasscodeRequirement = false
  #else
    private static let defaultPasscodeRequirement = true
  #endif

  private static let log = Logger(for: TrustAgentConfigUserDefaults.self)

  static let unlockHistoryKey = "UnlockHistoryEnabled"

  /// Default configuration values.
  ///
  /// A passcode is required by default before association and unlocking can begin.
  /// By default, the device must be unlocked before unlocking can begin.
  private static let defaultConfiguration = [
    isPasscodeRequiredKey: defaultPasscodeRequirement
  ]

  static let isPasscodeRequiredKey = "isPasscodeRequiredKey"
  static let trustedDeviceConfigurationKeyPrefix = "trustedDeviceConfigurationKeyPrefix"

  private let storage = UserDefaultsStorage.shared

  /// Whether a passcode is required for enrollment and unlocking.
  ///
  /// By default, this value is `true`.
  var isPasscodeRequired: Bool {
    get {
      return storage.bool(forKey: Self.isPasscodeRequiredKey)
    }
    set {
      storage.set(newValue, forKey: Self.isPasscodeRequiredKey)
    }
  }

  /// Whether unlock history should be kept by this manager.
  ///
  /// This value is read from an overlay plist. If the value or .plist does not exist, then this
  /// property will be `true` by default.
  let isUnlockHistoryEnabled: Bool

  /// Creates a new configuration manager that will also overlay any configuration values that are
  /// found by the given `pListLoader`.
  init(plistLoader: PListLoader) {
    storage.register(defaults: Self.defaultConfiguration)

    let overlayValues = plistLoader.loadOverlayValues()
    let isUnlockHistoryEnabled = overlayValues[Self.unlockHistoryKey] as? Bool
    self.isUnlockHistoryEnabled = isUnlockHistoryEnabled ?? true
  }

  /// Whether this device is required to be unlocked for unlocking the head unit.
  ///
  ///- Parameter car: The car to get the configuration of.
  func isDeviceUnlockRequired(for car: Car) -> Bool {
    return fetchIndividualCarConfig(for: car).isDeviceUnlockRequired
  }

  /// Set whether user needs to unlock the phone to unlock the car.
  ///
  /// - Parameters:
  ///   - car: The car to config.
  ///   - isRequired: The new value of the configuration.
  func setDeviceUnlockRequired(_ isRequired: Bool, for car: Car) {
    var savedConfig = fetchIndividualCarConfig(for: car)
    savedConfig.isDeviceUnlockRequired = isRequired
    saveIndividualCarConfig(config: savedConfig, for: car)
  }

  /// Returns `true` if the current device has all the necessary requirements for a passcode have
  /// been met.
  ///
  /// A value of `true` indicates that trust agent enrollment can proceed.
  ///
  /// - Returns: `true` if all passcode requirements are met.
  func arePasscodeRequirementsMet() -> Bool {
    return !isPasscodeRequired || System.canAuthenticateDevice
  }

  /// Returns `true` if the current device has all the necessary requirements for lock state.
  ///
  /// A value of `true` indicates that trust agent unlock can proceed
  ///
  ///- Parameter car: The car to unlock.
  func areLockStateRequirementsMet(for car: Car) -> Bool {
    return !isDeviceUnlockRequired(for: car) || System.isCurrentDeviceUnlocked
  }

  func clearConfig(for car: Car) {
    storage.remove(forKey: trustedDeviceConfigurationKey(forCarId: car.id))
  }

  private func fetchIndividualCarConfig(for car: Car) -> IndividualCarConfig {
    guard let savedConfig = storage.data(forKey: trustedDeviceConfigurationKey(forCarId: car.id))
    else {
      Self.log.debug(
        "No individual car configuration found for car id. Empty config will be returned.",
        redacting: "car id: \(car.id)"
      )
      return IndividualCarConfig()
    }
    guard let loadedConfig = try? JSONDecoder().decode(IndividualCarConfig.self, from: savedConfig)
    else {
      Self.log.error(
        "Cannot decode individual car configuration for car id. Empty config will be returned.",
        redacting: "car id: \(car.id)"
      )
      return IndividualCarConfig()
    }
    return loadedConfig
  }

  private func saveIndividualCarConfig(config: IndividualCarConfig, for car: Car) {
    guard let encoded = try? JSONEncoder().encode(config) else {
      Self.log.error(
        "Cannot encode individual car configuration for car id. Not saving config.",
        redacting: "car id: \(car.id)"
      )
      return
    }
    storage.set(encoded, forKey: trustedDeviceConfigurationKey(forCarId: car.id))
  }

  private func trustedDeviceConfigurationKey(forCarId carId: String) -> String {
    return Self.trustedDeviceConfigurationKeyPrefix + carId
  }
}

/// Data structure to store all car specific configuration.
struct IndividualCarConfig: Codable {
  /// Whether user needs to unlock the phone to unlock the car.
  var isDeviceUnlockRequired = true
}
