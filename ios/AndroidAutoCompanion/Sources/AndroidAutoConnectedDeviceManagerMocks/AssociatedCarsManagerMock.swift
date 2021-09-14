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

@testable import AndroidAutoConnectedDeviceManager

/// A mock of `AssociatedCarsManager` that simply sets its identifier internally and allows
/// assertions of its methods.
public class AssociatedCarsManagerMock: AssociatedCarsManager {
  private(set) var data: [String: String?] = [:]

  public var setIdentifierCalled = false
  public var clearIdentifierCalled = false

  public var identifiers: Set<String> {
    return Set(data.keys)
  }

  public var cars: Set<Car> {
    return Set(data.lazy.map { Car(id: $0, name: $1) })
  }

  public var count: Int {
    return data.count
  }

  public init() {}

  public func addAssociatedCar(identifier: String, name: String?) {
    setIdentifierCalled = true
    data[identifier] = name
  }

  public func clearIdentifiers() {
    data = [:]
  }

  public func clearIdentifier(_ identifier: String) {
    clearIdentifierCalled = true
    data[identifier] = nil
  }

  public func renameCar(identifier: String, to name: String) -> Bool {
    if data[identifier] == nil {
      return false
    }
    data[identifier] = name
    return true
  }

  /// Resets this mock back to its default initialization state
  public func reset() {
    data = [:]
    setIdentifierCalled = false
  }
}
