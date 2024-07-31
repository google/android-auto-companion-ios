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

import AndroidAutoCoreBluetoothProtocols
import CoreBluetooth
import Foundation

/// A mock for `BLECharacteristic` that allows its `uuid` and `value` to be set.
public class CharacteristicMock: NSObject, BLECharacteristic {
  public let uuid: CBUUID
  public var value: Data?
  public var serviceUUID: String? { nil }

  public init(uuid: CBUUID, value: Data?) {
    self.uuid = uuid
    self.value = value
  }
}
