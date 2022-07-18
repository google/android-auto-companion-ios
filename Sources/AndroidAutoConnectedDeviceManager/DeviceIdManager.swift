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

import AndroidAutoLogger
import CoreBluetooth
import Foundation

/// Manager for a id that will uniquely identify the current device.
enum DeviceIdManager {
  private static let log = Logger(for: DeviceIdManager.self)

  private static let deviceIdKey = "deviceIdKey"

  /// An id that uniquely identifies the current device.
  static var deviceId: CBUUID {
    if let deviceIdString = UserDefaultsStorage.shared.string(forKey: deviceIdKey) {
      return CBUUID(string: deviceIdString)
    }

    // CBUUID generates all 0 uuid by default, so need to use UUID first. >:(
    let randomUUID = CBUUID(string: UUID().uuidString)
    UserDefaultsStorage.shared.set(randomUUID.uuidString, forKey: deviceIdKey)

    log.debug("No previous device id found. Creating a new one: \(randomUUID.uuidString)")

    return randomUUID
  }
}
