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

/// A manager of unique identifiers for cars that have been previously associated with this
/// device.
protocol AssociatedCarsManager: AnyObject {
  /// The unique identifiers of the car that this device has previously connected and completed
  /// association with.
  var identifiers: Set<String> { get }

  /// The cars that have been successfully associated with this device.
  var cars: Set<Car> { get }

  /// The total number of devices, as counted by their unique ids, that have been associated.
  var count: Int { get }

  /// Adds to this car to the collection of successfully associated devices. Cars are uniquely
  /// uniquely identified by their identifier.
  ///
  /// Overwrites the existing name if the car has already been associated.
  ///
  /// - Parameters:
  ///   - identifier: The stream that is handling writing.
  ///   - name: The human-readable name of the device.
  func addAssociatedCar(identifier: String, name: String?)

  /// Clears any previously set identifiers for associated cars.
  func clearIdentifiers()

  /// Clears the specified identifier from the set of associated identifiers.
  ///
  /// - Parameter identifier: The identifier of the car to be removed.
  func clearIdentifier(_ identifier: String)

  /// Renames an associated car in persistent storage.
  ///
  /// - Parameters:
  ///   - identifier: The ID of the car to rename.
  ///   - name: The new name for the car.
  /// - Returns: `true` if the name was changed successfully.
  func renameCar(identifier: String, to name: String) -> Bool
}
