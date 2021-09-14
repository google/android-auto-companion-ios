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

/// An implementation of `TrustAgentManagerStorage` that delegates to `UserDefaults`.
class UserDefaultsTrustAgentManagerStorage: NSObject, TrustAgentManagerStorage {
  /// The key prefix to create an identifier for any feature status messages that need to be synced
  /// to the car.
  private static let carFeatureStatusPrefix = "trustAgent.featureStatus_"

  /// The key prefix to create an identifier for a car's unlock history.
  private static let carUnlockHistoryPrefix = "trustAgent.unlockHistory_"

  /// The maximum age in days for unlock history.
  private static let maxAgeDays = 7

  /// Adds to the unlock history for the car.
  ///
  /// - Parameters:
  ///   - date: The date to add to the unlock history.
  ///   - car: The car that has been unlocked.
  public func addUnlockDate(_ date: Date, for car: Car) {
    let key = Self.createUnlockKey(for: car)
    var existing = unlockHistory(for: car)
    existing.append(date)
    UserDefaults.standard.set(
      existing,
      forKey: key
    )
  }

  /// Clear unlock history for the car.
  ///
  /// - Parameter car: The car for which to clear the unlock history.
  public func clearUnlockHistory(for car: Car) {
    let key = Self.createUnlockKey(for: car)
    UserDefaults.standard.removeObject(forKey: key)
  }

  /// Clears stored unlock history for all cars.
  public func clearAllUnlockHistory() {
    let userDefaults = UserDefaults.standard

    userDefaults.dictionaryRepresentation().keys.forEach { key in
      if key.starts(with: Self.carUnlockHistoryPrefix) {
        userDefaults.removeObject(forKey: key)
      }
    }
  }

  /// Returns the unlock history for a car.
  ///
  /// No date older than the max age will be returned.
  ///
  /// - Parameter car: The car whose unlock history we want to retrieve.
  /// - Returns: The list of previous unlock dates, or an empty list if there is no history.
  public func unlockHistory(for car: Car) -> [Date] {
    let key = Self.createUnlockKey(for: car)
    let existing = UserDefaults.standard.array(forKey: key) as? [Date] ?? []
    let maxAgeDate = Calendar.current.date(
      byAdding: .day,
      value: -UserDefaultsTrustAgentManagerStorage.maxAgeDays,
      to: Date())
    let filtered = existing.filter({ $0 > maxAgeDate! })
    UserDefaults.standard.set(
      filtered,
      forKey: key
    )
    return filtered
  }

  /// Stores the status of the trusted device feature for the given car.
  ///
  /// - Parameters:
  ///   - status: The feature status to save.
  ///   - car: The car that corresponds to the saved feature status.
  func storeFeatureStatus(_ status: Data, for car: Car) {
    let key = Self.createStatusKey(for: car)
    UserDefaults.standard.set(status, forKey: key)
  }

  /// Returns any feature status for the given car.
  ///
  /// - Parameter car: The car to retrieve feature status for.
  /// - Returns: A stored status or `nil` if none exists.
  func featureStatus(for car: Car) -> Data? {
    let key = Self.createStatusKey(for: car)
    return UserDefaults.standard.data(forKey: key)
  }

  /// Clears any stored feature status for the given car.
  ///
  /// - Parameter car: The car to clear the feature status for.
  func clearFeatureStatus(for car: Car) {
    let key = Self.createStatusKey(for: car)
    UserDefaults.standard.removeObject(forKey: key)
  }

  /// Returns the key into `UserDefaults` that should be used to store the given car's unlock
  /// history.
  static func createUnlockKey(for car: Car) -> String {
    return carUnlockHistoryPrefix + car.id
  }

  /// Returns the key into `UserDefaults` that should be used to store any feature status messages
  /// that should be synced to the given car.
  static func createStatusKey(for car: Car) -> String {
    return carFeatureStatusPrefix + car.id
  }
}
