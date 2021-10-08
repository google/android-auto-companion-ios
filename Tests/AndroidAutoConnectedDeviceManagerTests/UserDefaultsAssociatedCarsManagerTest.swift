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

import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `UserDefaultsAssociatedCarsManager`.
class UserDefaultsAssociatedCarsManagerTest: XCTestCase {
  private let storage = UserDefaultsAssociatedCarsManager()

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() {
    UserDefaults.standard.removeObject(
      forKey: UserDefaultsAssociatedCarsManager.connectedCarIdentifierKey
    )
  }

  func testAddAssociatedCar() {
    let car1 = Car(id: "id1", name: "name1")
    let car2 = Car(id: "id2", name: "name2")

    storage.addAssociatedCar(identifier: car1.id, name: car1.name)
    storage.addAssociatedCar(identifier: car2.id, name: car2.name)

    XCTAssertEqual(storage.identifiers.count, 2)
    XCTAssert(storage.identifiers.contains(car1.id))
    XCTAssert(storage.identifiers.contains(car2.id))

    XCTAssertEqual(storage.cars.count, 2)
    XCTAssert(storage.cars.contains(car1))
    XCTAssert(storage.cars.contains(car2))

    XCTAssertEqual(storage.count, 2)
  }

  func testClearIdentifier_clearsIdentifier() {
    let car1 = Car(id: "id1", name: "name1")
    let car2 = Car(id: "id2", name: "name2")

    storage.addAssociatedCar(identifier: car1.id, name: car1.name)
    storage.addAssociatedCar(identifier: car2.id, name: car2.name)
    storage.clearIdentifier(car1.id)

    XCTAssertEqual(storage.identifiers.count, 1)
    XCTAssert(storage.identifiers.contains(car2.id))

    XCTAssertEqual(storage.cars.count, 1)
    XCTAssert(storage.cars.contains(car2))

    XCTAssertEqual(storage.count, 1)
  }

  func testClearIdentifiers() {
    let car1 = Car(id: "id1", name: "name1")
    let car2 = Car(id: "id2", name: "name2")

    storage.addAssociatedCar(identifier: car1.id, name: car1.name)
    storage.addAssociatedCar(identifier: car2.id, name: car2.name)
    storage.clearIdentifiers()

    XCTAssert(storage.identifiers.isEmpty)
    XCTAssert(storage.cars.isEmpty)
    XCTAssertEqual(storage.count, 0)
  }

  func testRenameCar() {
    let car1 = Car(id: "id1", name: "name1")
    let car2 = Car(id: "id2", name: "name2")
    let newName = "newName"

    storage.addAssociatedCar(identifier: car1.id, name: car1.name)
    storage.addAssociatedCar(identifier: car2.id, name: car2.name)
    XCTAssertTrue(storage.renameCar(identifier: car1.id, to: newName))

    // No change to the number of cars.
    XCTAssertEqual(storage.identifiers.count, 2)
    XCTAssertEqual(storage.cars.count, 2)
    XCTAssertEqual(storage.count, 2)

    XCTAssert(storage.cars.contains(where: { $0.name == newName }))
    XCTAssert(storage.cars.contains(where: { $0.name == car2.name }))
  }
}
