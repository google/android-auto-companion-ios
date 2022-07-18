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

/// A wrapper around `CBSService` that will make it conform to `BLEService`.
class CBServiceWrapper: NSObject, BLEService {
  let service: CBService

  var uuid: CBUUID {
    return service.uuid
  }

  var characteristics: [BLECharacteristic]? {
    return service.characteristics?.map { CBCharacteristicWrapper(characteristic: $0) }
  }

  init(service: CBService) {
    self.service = service
  }
}
