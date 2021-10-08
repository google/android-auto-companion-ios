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
@_implementationOnly import AndroidAutoMessageStream
import Foundation

/// A car that is pending establishment of a secure channel.
class PendingCar {
  let car: BLEPeripheral

  let id: String?
  let secureSession: Data?
  var messageStream: MessageStream?

  /// The characteristic on the car that the car will write values to.
  var readCharacteristic: BLECharacteristic?

  /// The characteristic on the car that can be used to write values to.
  var writeCharacteristic: BLECharacteristic?

  /// Initialize this struct with just the car that is waiting for a secure channel.
  ///
  /// - Parameter car: the peripheral that backs this `PendingCar`.
  init(car: BLEPeripheral) {
    self.car = car
    self.id = nil
    self.secureSession = nil
  }

  /// Initializes this struct with the basic signals for reestablishing a secure session.
  ///
  /// The secure session passed should be the result of a `SecureBLEChannel.saveSession()` call.
  /// This secure session should be one that was previously established with the given
  /// `BLEPeripheral`.
  ///
  /// - Parameters:
  ///   - car: The car to establish a secure channel with.
  ///   - id: The unique identifier for the car.
  ///   - secureSession: Serialized data for reestablishing a secure session with the given car.
  init(car: BLEPeripheral, id: String, secureSession: Data) {
    self.id = id
    self.car = car
    self.secureSession = secureSession
  }
}

extension PendingCar: Hashable {
  static func == (lhs: PendingCar, rhs: PendingCar) -> Bool {
    return lhs.id == rhs.id && lhs.car.identifier == rhs.car.identifier
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
    hasher.combine(car.identifier)
  }
}
