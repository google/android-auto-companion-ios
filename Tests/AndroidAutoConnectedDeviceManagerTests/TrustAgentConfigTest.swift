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

/// Tests for `TrustAgentConfig`.
@available(watchOS 6.0, *)
class TrustAgentConfigTest: XCTestCase {
  private let storage = UserDefaultsStorage.shared
  private let testCar = Car(id: "carId", name: "carName")

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
    storage.clearAll()
  }

  func testIsPasscodeRequired_defaultValueIsTrue() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())

    XCTAssertTrue(config.isPasscodeRequired)

    // Check that the value is actually stored in persistent storage.
    XCTAssertTrue(storage.bool(forKey: TrustAgentConfigUserDefaults.isPasscodeRequiredKey))
  }

  func testIsPasscodeRequired_setValue() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())

    config.isPasscodeRequired = false
    XCTAssertFalse(config.isPasscodeRequired)
    XCTAssertFalse(storage.bool(forKey: TrustAgentConfigUserDefaults.isPasscodeRequiredKey))

    config.isPasscodeRequired = true
    XCTAssertTrue(config.isPasscodeRequired)
    XCTAssertTrue(storage.bool(forKey: TrustAgentConfigUserDefaults.isPasscodeRequiredKey))
  }

  func testIsDeviceUnlockRequired_defaultValueIsTrue() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())
    XCTAssertTrue(config.isDeviceUnlockRequired(for: testCar))
  }

  func testSetDeviceUnlockRequired_updateValue() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())

    config.setDeviceUnlockRequired(false, for: testCar)
    XCTAssertFalse(config.isDeviceUnlockRequired(for: testCar))

    let savedConfig1 = storage.data(
      forKey: TrustAgentConfigUserDefaults.trustedDeviceConfigurationKeyPrefix + testCar.id)
    XCTAssertNotNil(savedConfig1)
    if let loadedConfig1 = try? JSONDecoder().decode(IndividualCarConfig.self, from: savedConfig1!)
    {
      let _ = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())
      XCTAssertFalse(loadedConfig1.isDeviceUnlockRequired)
    }

    config.setDeviceUnlockRequired(true, for: testCar)
    XCTAssertTrue(config.isDeviceUnlockRequired(for: testCar))
    let savedConfig2 = storage.data(
      forKey: TrustAgentConfigUserDefaults.trustedDeviceConfigurationKeyPrefix + testCar.id)
    XCTAssertNotNil(savedConfig2)
    if let loadedConfig2 = try? JSONDecoder().decode(IndividualCarConfig.self, from: savedConfig2!)
    {
      let _ = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())
      XCTAssertTrue(loadedConfig2.isDeviceUnlockRequired)
    }
  }

  func testRemove_clearConfigurationForCar() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())
    config.setDeviceUnlockRequired(true, for: testCar)
    XCTAssertTrue(config.isDeviceUnlockRequired(for: testCar))

    config.clearConfig(for: testCar)

    XCTAssertTrue(config.isDeviceUnlockRequired(for: testCar))
  }

  func testUnlockHistoryEnabled_defaultIsTrue() {
    let config = TrustAgentConfigUserDefaults(plistLoader: PListLoaderFake())
    XCTAssertTrue(config.isUnlockHistoryEnabled)
  }

  func testUnlockHistoryEnabled_loadsFromOverlayValue() {
    let plistLoader = PListLoaderFake(
      overlayValues: [TrustAgentConfigUserDefaults.unlockHistoryKey: false]
    )
    let config = TrustAgentConfigUserDefaults(plistLoader: plistLoader)

    XCTAssertFalse(config.isUnlockHistoryEnabled)
  }
}
