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

public import CoreBluetooth
internal import Foundation

/// A BLE characteristic.
public protocol BLECharacteristic: AnyObject {
  /// The Bluetooth-specific UUID of the characteristic.
  var uuid: CBUUID { get }

  /// The value of this characteristic.
  var value: Data? { get }

  /// UUID of the characteristic's service.
  var serviceUUID: String? { get }
}
