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

import AndroidAutoMessageStream
import CoreBluetooth

@testable import AndroidAutoConnectedDeviceManager

/// Mock for the ReconnectionHelper so we can track calls from tests.
final public class ReconnectionHelperMock {
  // MARK: - Configuration
  public var shouldThrowInvalidMessage = false
  public var shouldCompleteHandshake = true
  public var securityVersion: MessageSecurityVersion = .v2
  public var isReadyForHandshake = true
  public var prepareForHandshakeShouldSucceed = true
  public var configureSecureChannelShouldSucceed = true

  /// The Car ID to use once the handshake is complete.
  private var pendingCarId: String

  // MARK: - Method call checks
  public var startHandshakeCalled = false
  public var onResolvedSecurityVersionCalled = false
  public var handleMessageCalled = false
  public var prepareForHandshakeCalled = false

  // MARK: - ReconnectionHelper Stored Properties
  public var carId: String?
  public let peripheral: AnyPeripheral
  public var onReadyForHandshake: (() -> Void)?

  /// Initializer for variant where the carId comes in a later message.
  public init(peripheral: AnyPeripheral, pendingCarId: String) {
    self.peripheral = peripheral
    self.pendingCarId = pendingCarId
  }
}

// MARK: - ReconnectionHelper
extension ReconnectionHelperMock: ReconnectionHelper {
  public func discoveryUUID(from config: UUIDConfig) -> CBUUID {
    config.reconnectionUUID(for: securityVersion)
  }

  public func prepareForHandshake(withAdvertisementData data: Data) throws {
    prepareForHandshakeCalled = true

    if prepareForHandshakeShouldSucceed {
      isReadyForHandshake = true
    } else {
      isReadyForHandshake = false
      throw CommunicationManagerError.unassociatedCar
    }
  }

  public func onResolvedSecurityVersion(_ version: MessageSecurityVersion) throws {
    onResolvedSecurityVersionCalled = true
  }

  public func startHandshake(messageStream: MessageStream) {
    startHandshakeCalled = true
  }

  public func handleMessage(messageStream: MessageStream, message: Data) throws -> Bool {
    handleMessageCalled = true

    if shouldThrowInvalidMessage {
      throw CommunicationManagerError.invalidMessage
    }

    if shouldCompleteHandshake {
      carId = pendingCarId
    }

    return shouldCompleteHandshake
  }

  public func configureSecureChannel(
    _: SecuredConnectedDeviceChannel,
    using connectionHandle: ConnectionHandle,
    completion: (Bool) -> Void
  ) {
    completion(configureSecureChannelShouldSucceed)
  }
}
