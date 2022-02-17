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

/// Utility that manages information about cars that this device has attempted to associate with.
class UserDefaultsAssociatedCarsManager: NSObject, AssociatedCarsManager {
  // The key for an identifier that will identify a previously associated device.
  static let connectedCarIdentifierKey = "connectedCarIdentifier"

  /// The unique identifiers of the car that this device has previously connected and completed
  /// association with.
  var identifiers: Set<String> {
    let dict =
      UserDefaults.standard.dictionary(
        forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
      ) ?? [:]
    return Set(dict.keys)
  }

  /// The cars that have been successfully associated with this device.
  var cars: Set<Car> {
    let dict =
      UserDefaults.standard.dictionary(
        forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
      ) ?? [:]
    return Set(dict.lazy.map { Car(id: $0, name: $1 as? String) })
  }

  /// The total number of devices, as counted by their unique ids, that have been associated.
  var count: Int {
    return identifiers.count
  }

  /// Adds the given string to uniquely identify a car that this device has been successfully
  /// associated.
  ///
  /// Overwrites the existing name if the car has already been associated.
  ///
  /// - Parameters:
  ///   - identifier: The stream that is handling writing.
  ///   - name: The human-readable name of the device.
  func addAssociatedCar(identifier: String, name: String?) {
    var existing =
      UserDefaults.standard.dictionary(
        forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
      ) ?? [:]
    existing[identifier] = name
    UserDefaults.standard.set(
      existing,
      forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
    )
  }

  /// Clears any previously set identifiers for associated cars.
  func clearIdentifiers() {
    UserDefaults.standard.removeObject(
      forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
    )
  }

  /// Clears the specified identifier from the set of associated identifiers.
  ///
  /// - Parameter identifier: The identifier of the car to be removed.
  func clearIdentifier(_ identifier: String) {
    var existing =
      UserDefaults.standard.dictionary(
        forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
      ) ?? [:]
    existing[identifier] = nil
    UserDefaults.standard.set(
      existing,
      forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
    )
  }

  /// Renames an associated car in persistent storage.
  ///
  /// - Parameters:
  ///   - identifier: The ID of the car to rename.
  ///   - name: The new name for the car.
  /// - Returns: `true` if the name was changed successfully.
  func renameCar(identifier: String, to name: String) -> Bool {
    var existing =
      UserDefaults.standard.dictionary(
        forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
      ) ?? [:]
    if existing[identifier] == nil {
      return false
    }
    existing[identifier] = name
    UserDefaults.standard.set(
      existing,
      forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
    )
    return true
  }
}
