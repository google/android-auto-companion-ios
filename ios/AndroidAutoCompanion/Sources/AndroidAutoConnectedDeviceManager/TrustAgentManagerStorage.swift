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

/// Protocol for a class that can handle storage for `TrustAgentManager`
protocol TrustAgentManagerStorage {

  /// Adds to the unlock history for the car.
  ///
  /// - Parameters:
  ///   - date: The date to add to the unlock history.
  ///   - car: The car that has been unlocked.
  func addUnlockDate(_ date: Date, for car: Car)

  /// Clear unlock history for the car.
  ///
  /// - Parameter car: The car for which to clear the unlock history.
  func clearUnlockHistory(for car: Car)

  /// Clears stored unlock history for all cars.
  func clearAllUnlockHistory()

  /// Returns the unlock history for a car.
  ///
  /// - Parameter car: The car whose unlock history we want to retrieve.
  /// - Returns: The list of previous unlock dates, or an empty list if there is no history.
  func unlockHistory(for car: Car) -> [Date]

  /// Stores the status of the trusted device feature for the given car.
  ///
  /// The stored data should be the exact value that can be sent to the car for syncing the state
  /// of a trusted device.
  ///
  /// - Parameters:
  ///   - status: The feature status to save.
  ///   - car: The car that corresponds to the saved feature status.
  func storeFeatureStatus(_ status: Data, for car: Car)

  /// Returns any feature status for the given car.
  ///
  /// The returned data can be sent as-is to the car to sync the state of trusted device.
  ///
  /// - Parameter car: The car to retrieve feature status for.
  /// - Returns: A stored status or `nil` if none exists.
  func featureStatus(for car: Car) -> Data?

  /// Clears any stored feature status for the given car.
  ///
  /// - Parameter car: The car to clear the feature status for.
  func clearFeatureStatus(for car: Car)
}
