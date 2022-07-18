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

/// A fake `TrustAgentConfig` that stores values in memory.
public class TrustAgentConfigFake: TrustAgentConfig {
  /// `true` to simulate the user setting a password on the current device.
  public var isPasscodeSet = false

  /// `true` to simulate the current phone being unlocked.
  public var isDeviceUnlocked = false

  public var isPasscodeRequired = false
  public var isUnlockHistoryEnabled = true

  private var isDeviceUnlockRequiredMap: [String: Bool] = [:]
  private var shouldShowNotificationMap: [String: Bool] = [:]

  public init() {}

  public func isDeviceUnlockRequired(for car: Car) -> Bool {
    return isDeviceUnlockRequiredMap[car.id] ?? false
  }

  public func setDeviceUnlockRequired(_ isRequired: Bool, for car: Car) {
    isDeviceUnlockRequiredMap[car.id] = isRequired
  }

  public func shouldShowUnlockNotification(for car: Car) -> Bool {
    return shouldShowNotificationMap[car.id] ?? false
  }

  public func setShowUnlockNotification(_ shouldShow: Bool, for car: Car) {
    shouldShowNotificationMap[car.id] = shouldShow
  }

  public func arePasscodeRequirementsMet() -> Bool {
    return !isPasscodeRequired || isPasscodeSet
  }

  public func areLockStateRequirementsMet(for car: Car) -> Bool {
    return !isDeviceUnlockRequired(for: car) || isDeviceUnlocked
  }

  public func clearConfig(for car: Car) {
    isDeviceUnlockRequiredMap.removeValue(forKey: car.id)
  }
}
