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

@testable import AndroidAutoConnectedDeviceManager

/// A fake `TrustAgentManagerStorage` that stores values in memory.
public class TrustAgentManagerStorageFake: TrustAgentManagerStorage {
  private var unlockHistory = [Car: [Date]]()
  private var featureStatuses = [Car: Data]()

  public init() {}

  /// Adds to the unlock history for the car.
  ///
  /// - Parameters:
  ///   - date: The date to add to the unlock history.
  ///   - car: The car that has been unlocked.
  public func addUnlockDate(_ date: Date, for car: Car) {
    var history = self.unlockHistory(for: car)
    history.append(date)
    unlockHistory[car] = history
  }

  /// Clear unlock history for the car.
  ///
  /// - Parameter car: The car for which to clear the unlock history.
  public func clearUnlockHistory(for car: Car) {
    unlockHistory[car] = []
  }

  /// Clears unlock history for all cars.
  public func clearAllUnlockHistory() {
    unlockHistory = [:]
  }

  /// Returns the unlock history for a car.
  ///
  /// - Parameter car: The car whose unlock history we want to retrieve.
  /// - Returns: The list of previous unlock dates, or an empty list if there is no history.
  public func unlockHistory(for car: Car) -> [Date] {
    return unlockHistory[car, default: []]
  }

  /// Stores the status of the trusted device feature for the given car.
  public func storeFeatureStatus(_ status: Data, for car: Car) {
    featureStatuses[car] = status
  }

  /// Returns any feature status for the given car.
  public func featureStatus(for car: Car) -> Data? {
    return featureStatuses[car]
  }

  /// Clears any stored feature status for the given car.
  public func clearFeatureStatus(for car: Car) {
    featureStatuses[car] = nil
  }

  /// Resets back to the default initialization state.
  public func reset() {
    unlockHistory = [:]
    featureStatuses = [:]
  }
}
