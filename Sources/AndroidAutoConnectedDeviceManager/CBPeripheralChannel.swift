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

@_implementationOnly import AndroidAutoConnectedDeviceTransport
@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import AndroidAutoLogger
import CoreBluetooth
import Foundation
@_implementationOnly import AndroidAutoCompanionProtos

/// Channel for maintaining BLE streams for communication.
class CBPeripheralChannel: TransportChannel {
  /// Peripheral for which the channel is providing communication.
  var peripheral: CBPeripheralRef

  /// Receiver of read events.
  var onMessageRead: ((Result<Data, TransportChannelError>) -> Void)? = nil

  init(peripheral: CBPeripheralRef) {
    self.peripheral = peripheral
  }

  /// Send a message.
  func writeMessage(
    _ message: Data,
    completion: ((TransportChannelError?) -> Void)?
  ) {
    // TODO(b/185591036): Implement.
  }
}
