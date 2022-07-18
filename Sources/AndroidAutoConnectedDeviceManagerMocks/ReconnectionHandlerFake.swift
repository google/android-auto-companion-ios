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
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A `ReconnectionHandler` that also supports the ability to trigger the establishment of
/// encryption.
public class ReconnectionHandlerFake: ReconnectionHandler {
  public let car: Car
  public let peripheral: BLEPeripheral

  public var establishEncryptionShouldFail = false
  public var establishEncryptionCalled = false

  public weak var delegate: ReconnectionHandlerDelegate?

  public init(car: Car, peripheral: BLEPeripheral) {
    self.car = car
    self.peripheral = peripheral
  }

  public func establishEncryption() throws {
    establishEncryptionCalled = true
    if establishEncryptionShouldFail {
      throw NSError(domain: "Test", code: 1, userInfo: nil)
    }
  }

  /// Simulates an establishment of a secure channel.
  ///
  /// When this method is called, any `delegate` that is set on this class will be notified with
  /// a `SecuredCarChannelMock`.
  public func notifyEncryptionEstablished() {
    delegate?.reconnectionHandler(
      self,
      didEstablishSecureChannel: SecuredCarChannelMock(car: car)
    )
  }
}
