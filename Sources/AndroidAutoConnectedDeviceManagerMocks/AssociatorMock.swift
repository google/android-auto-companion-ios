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

/// Mock for the Associator so we can track calls from tests.
@MainActor final public class AssociatorMock {
  // MARK: - Configuration
  public var shouldThrowWhenNotifyingPairingCodeAccepted = false

  // MARK: - Method call checks
  public var establishEncryptionCalled = false
  public var establishSecuredCarChannelCalled = false
  public var completeAssociationCalled = false
  public var requestOutOfBandTokenCalled = false
  public var displayPairingCodeCalled = false
  public var notifyPairingCodeAcceptedCalled = false
  public var notifyDelegateOfErrorCalled = false
  public var associationError: AssociationError?

  // MARK: - Associator Stored Properties
  public var connectionHandle: ConnectionHandle = ConnectionHandleFake()
  public var carId: String?

  public var outOfBandToken: OutOfBandToken?
  public var securedChannel: SecuredConnectedDeviceChannel?

  /// `true` if a call to `establishSecuredCarChannel(forCarId:messageStream:)` should succeed.
  public var establishSecuredCarChannelSucceeds = true

  public init() {}
}

// MARK: - Associator
extension AssociatorMock: Associator {
  public func establishEncryption(using messageStream: MessageStream) {
    establishEncryptionCalled = true
  }

  /// Saves the secure session and establishes a secured car channel.
  public func establishSecuredCarChannel(
    forCarId carId: String,
    messageStream: MessageStream
  ) -> SecuredConnectedDeviceChannel? {
    guard establishSecuredCarChannelSucceeds else {
      return nil
    }

    if let carId = self.carId {
      securedChannel = SecuredCarChannelMock(id: carId, name: "test")
    }
    establishSecuredCarChannelCalled = true
    return securedChannel
  }

  /// Completes any remaining association work and notifies the delegate that
  /// association is complete.
  public func completeAssociation(
    channel: SecuredConnectedDeviceChannel, messageStream: MessageStream
  ) {
    completeAssociationCalled = true
  }

  /// Request an out of band token.
  public func requestOutOfBandToken(completion: @escaping (OutOfBandToken?) -> Void) {
    requestOutOfBandTokenCalled = true
    completion(outOfBandToken)
  }

  /// Display the specified pairing code for visual verification.
  public func displayPairingCode(_ pairingCode: String) {
    displayPairingCodeCalled = true
  }

  public func notifyDelegateOfError(_ error: AssociationError) {
    associationError = error
    notifyDelegateOfErrorCalled = true
  }

  public func notifyPairingCodeAccepted() throws {
    notifyPairingCodeAcceptedCalled = true
    if shouldThrowWhenNotifyingPairingCodeAccepted {
      throw AssociationError.unknown
    }
  }
}
