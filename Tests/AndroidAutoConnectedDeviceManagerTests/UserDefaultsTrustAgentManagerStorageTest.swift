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

/// Unit tests for `UserDefaultsTrustAgentManagerStorage`.
class UserDefaultsTrustAgentManagerStorageTest: XCTestCase {

  private let car = Car(id: "identifier", name: "name")
  private let car2 = Car(id: "identifier2", name: "name2")

  private let storage = UserDefaultsTrustAgentManagerStorage()

  override func tearDown() {
    // alternatively the class in test could be refactored to use UserDefaults(suiteName: )
    UserDefaults.standard.removeObject(
      forKey: UserDefaultsTrustAgentManagerStorage.createUnlockKey(for: car))
    UserDefaults.standard.removeObject(
      forKey: UserDefaultsTrustAgentManagerStorage.createStatusKey(for: car))
  }

  func testUnlockHistory_noHistory_isEmpty() {
    XCTAssert(storage.unlockHistory(for: car).isEmpty)

    // unlockHistory has a side-effect (re-saving the history) - verify this works a second time
    XCTAssert(storage.unlockHistory(for: car).isEmpty)
  }

  // MARK: - Unlock history tests

  func testClearUnlockHistory_historyIsEmpty() {
    let now = Date()
    let earlier = now.addingTimeInterval(-1000)

    storage.addUnlockDate(now, for: car)
    storage.addUnlockDate(earlier, for: car)

    storage.clearUnlockHistory(for: car)
    XCTAssert(storage.unlockHistory(for: car).isEmpty)
  }

  func testStoringUnlockHistory_savesSingleDate() {
    let now = Date()

    storage.addUnlockDate(now, for: car)
    XCTAssert(storage.unlockHistory(for: car).contains(now))
  }

  func testStoringUnlockHistory_savesMultipleDates() {
    let now = Date()
    let earlier = now.addingTimeInterval(-1000)

    storage.addUnlockDate(now, for: car)
    storage.addUnlockDate(earlier, for: car)
    XCTAssert(storage.unlockHistory(for: car).contains(now))
    XCTAssert(storage.unlockHistory(for: car).contains(earlier))
  }

  func testStoringUnlockHistory_oldDatesAreCleared() {
    let beginningOfTime = Date(timeIntervalSince1970: 0)

    storage.addUnlockDate(beginningOfTime, for: car)
    XCTAssert(storage.unlockHistory(for: car).isEmpty)
  }

  func testClearUnlockHistory() {
    storage.addUnlockDate(Date(), for: car)
    storage.clearUnlockHistory(for: car)
    XCTAssertTrue(storage.unlockHistory(for: car).isEmpty)
  }

  func testClearAllUnlockHistory() {
    storage.addUnlockDate(Date(), for: car)
    storage.addUnlockDate(Date(), for: car2)
    storage.clearAllUnlockHistory()
    XCTAssertTrue(storage.unlockHistory(for: car).isEmpty)
    XCTAssertTrue(storage.unlockHistory(for: car2).isEmpty)
  }

  // MARK: - Feature status tests

  func testStoreFeatureStatus() {
    let status = Data("status".utf8)
    let otherStatus = Data("otherStatus".utf8)
    let otherCar = Car(id: "other", name: "other")

    storage.storeFeatureStatus(status, for: car)
    storage.storeFeatureStatus(otherStatus, for: otherCar)

    XCTAssertEqual(storage.featureStatus(for: car), status)
    XCTAssertEqual(storage.featureStatus(for: otherCar), otherStatus)
  }

  func testStoreFeatureStatus_emptyIfNothingStored() {
    XCTAssertNil(storage.featureStatus(for: car))
  }

  func testClearFeatureStatus() {
    let status = Data("status".utf8)
    let otherStatus = Data("otherStatus".utf8)
    let otherCar = Car(id: "other", name: "other")

    storage.storeFeatureStatus(status, for: car)
    storage.storeFeatureStatus(otherStatus, for: otherCar)
    storage.clearFeatureStatus(for: car)

    XCTAssertNil(storage.featureStatus(for: car))
    XCTAssertEqual(storage.featureStatus(for: otherCar), otherStatus)
  }
}
