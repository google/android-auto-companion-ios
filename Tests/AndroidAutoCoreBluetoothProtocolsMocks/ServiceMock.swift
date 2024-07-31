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

/// A mock that allows the service `uuid` and `characteristics` to be set.
public class ServiceMock: BLEService {
  public let uuid: CBUUID
  public var characteristics: [BLECharacteristic]?

  public init(uuid: CBUUID, characteristics: [BLECharacteristic]?) {
    self.uuid = uuid
    self.characteristics = characteristics
  }

  /// Constructor that will create a `ServiceMock` with `nil` characteristics.
  public convenience init(uuid: CBUUID) {
    self.init(uuid: uuid, characteristics: nil)
  }
}
