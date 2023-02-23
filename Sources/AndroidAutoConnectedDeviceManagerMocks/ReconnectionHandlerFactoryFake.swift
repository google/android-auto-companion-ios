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
import AndroidAutoMessageStream
import AndroidAutoSecureChannel
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A creator of fake `ReconnectionHandler`s.
public class ReconnectionHandlerFactoryFake: ReconnectionHandlerFactory {
  // When making channels, sets `establishEncryptionShouldFail` accordingly.
  public var makeChannelEstablishEncryptionShouldFail = false

  public var createdChannels: [ReconnectionHandlerFake] = []

  public init() {}

  @MainActor public func makeHandler(
    car: Car,
    connectionHandle: ConnectionHandle,
    secureSession: Data,
    messageStream: BLEMessageStream,
    secureBLEChannel: SecureBLEChannel,
    secureSessionManager: SecureSessionManager
  ) -> ReconnectionHandler {
    let channel = ReconnectionHandlerFake(car: car, peripheral: messageStream.peripheral)
    channel.establishEncryptionShouldFail = makeChannelEstablishEncryptionShouldFail
    createdChannels.append(channel)
    return channel
  }

  public func reset() {
    createdChannels = []
  }
}
