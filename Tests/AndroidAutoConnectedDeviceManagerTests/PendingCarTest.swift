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

import AndroidAutoCoreBluetoothProtocolsMocks
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `PendingCar`.
class PendingCarTest: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testPendingCar_sameId_samePeripheralId_areEqual() {
    let peripheralId = UUID(uuidString: "af90316a-ce96-41be-86d1-38ceb70f9245")!
    let carId = "id"

    let peripheralMock1 = PeripheralMock(name: "car1")
    peripheralMock1.identifier = peripheralId
    let car1 = PendingCar(car: peripheralMock1, id: carId, secureSession: Data())

    let peripheralMock2 = PeripheralMock(name: "car2")
    peripheralMock2.identifier = peripheralId
    let car2 = PendingCar(car: peripheralMock2, id: carId, secureSession: Data())

    XCTAssertEqual(car1, car2)
  }

  func testPendingCar_sameId_differentPeripheralId_areNotEqual() {
    let carId = "id"

    let peripheralMock1 = PeripheralMock(name: "car1")
    peripheralMock1.identifier = UUID(uuidString: "af90316a-ce96-41be-86d1-38ceb70f9245")!
    let car1 = PendingCar(car: peripheralMock1, id: carId, secureSession: Data())

    let peripheralMock2 = PeripheralMock(name: "car2")
    peripheralMock1.identifier = UUID(uuidString: "87a7d62f-910a-4b22-bd1c-6b0071dc5353")!
    let car2 = PendingCar(car: peripheralMock2, id: carId, secureSession: Data())

    XCTAssertNotEqual(car1, car2)
  }

  func testPendingCar_differentId_samePeripheralId_areNotEqual() {
    let peripheralId = UUID(uuidString: "af90316a-ce96-41be-86d1-38ceb70f9245")!

    let peripheralMock1 = PeripheralMock(name: "car1")
    peripheralMock1.identifier = peripheralId
    let car1 = PendingCar(car: peripheralMock1, id: "id1", secureSession: Data())

    let peripheralMock2 = PeripheralMock(name: "car2")
    peripheralMock1.identifier = peripheralId
    let car2 = PendingCar(car: peripheralMock2, id: "id2", secureSession: Data())

    XCTAssertNotEqual(car1, car2)
  }

  func testPendingCar_differentSecureSession_areEqual() {
    let peripheralId = UUID(uuidString: "af90316a-ce96-41be-86d1-38ceb70f9245")!
    let carId = "id"

    let peripheralMock1 = PeripheralMock(name: "car1")
    peripheralMock1.identifier = peripheralId
    let car1 = PendingCar(car: peripheralMock1, id: carId, secureSession: Data("session1".utf8))

    let peripheralMock2 = PeripheralMock(name: "car2")
    peripheralMock2.identifier = peripheralId
    let car2 = PendingCar(car: peripheralMock2, id: carId, secureSession: Data("session2".utf8))

    XCTAssertEqual(car1, car2)
  }
}
