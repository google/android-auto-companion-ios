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

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import CoreBluetooth
import Foundation

/// A wrapper around `CBCharacteristic` that will make it conform to `BLECharacteristic`.
///
/// Although `CBCharacteristic` conforms without needing to add any extra logic, this wrapping class
/// is required because `CoreBluetoothProtocols` is an implementation-only import. Thus, the
/// following cannot be done or else `BLECharacteristic` will need to be exposed as public:
///
/// ```
/// extension CBCharacteristic: BLECharacteristic {}
/// ```
class CBCharacteristicWrapper: BLECharacteristic {
  let characteristic: CBCharacteristic

  var uuid: CBUUID {
    return characteristic.uuid
  }

  var serviceUUID: String? { characteristic.service?.uuid.uuidString }

  var value: Data? {
    return characteristic.value
  }

  init(characteristic: CBCharacteristic) {
    self.characteristic = characteristic
  }
}
