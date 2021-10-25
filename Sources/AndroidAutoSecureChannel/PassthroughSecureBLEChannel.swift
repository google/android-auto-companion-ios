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
import Foundation

/// The possible errors that can occur during the establishment of a secure channel.
enum PassthroughSecureBLEChannelError: Error {
  /// Indicates that the methods of this function were called out of order.
  case methodsCalledOutOfOrder
}

/// An extension of the error that sets a message describing the cause.
extension PassthroughSecureBLEChannelError: LocalizedError {
  public var errorDescription: String? {
    return "Secure channel methods called out of order."
  }
}

/// An implementation of a secure channel for testing purposes.
///
/// This class simply states that a secure channel has been established if its methods are called
/// in the correct order.
///
/// Encrypting and decrypting a message returns the same message.
class PassthroughSecureBLEChannel: SecureBLEChannel {
  /// Token used for verification when establishing a UKey2 channel.
  struct VerificationToken: SecurityVerificationToken {
    /// Full backing data.
    var data: Data { Data(pairingCode.utf8) }

    /// Human-readable visual pairing code derived from the full data.
    let pairingCode: String = "000000"
  }

  private var messageStream: MessageStream?

  /// The state of the secure channel.
  private(set) var state: SecureBLEChannelState = .uninitialized

  /// A delegate that will be notified of various events with the secure channel.
  weak var delegate: SecureBLEChannelDelegate?

  /// Sets that a secure channel has been established with the given peripheral.
  ///
  /// This method must be called before any other method of this class.
  ///
  /// - Parameter messageStream: The stream used to send messages.
  /// - Throws: An generic error or one of type `UKey2ChannelError`.
  func establish(using messageStream: MessageStream) throws {
    self.messageStream = messageStream

    state = .inProgress

    delegate?.secureBLEChannel(
      self,
      requiresVerificationOf: VerificationToken(),
      messageStream: messageStream
    )
  }

  func establish(
    using messageStream: MessageStream,
    withSavedSession savedSession: Data
  ) throws {
    // Just immediately establish because there's nothing to restore. This makes it so that the
    // pairing code does not show.
    state = .established
    delegate?.secureBLEChannel(self, establishedUsing: messageStream)
  }

  /// Notifies this secure channel that the pairing code has been accepted by the user.
  ///
  /// The pairing code to be confirmed should be passed to a set delegate with a call to
  /// `secureBLEChannel(_:requiresVerifitionOf:for:)` method.
  func notifyPairingCodeAccepted() throws {
    guard state == .inProgress, let messageStream = messageStream else {
      delegate?.secureBLEChannel(
        self,
        encounteredError: PassthroughSecureBLEChannelError.methodsCalledOutOfOrder
      )
      return
    }

    state = .established

    messageStream.messageEncryptor = self
    delegate?.secureBLEChannel(self, establishedUsing: messageStream)

    self.messageStream = nil
  }

  func saveSession() throws -> Data {
    // Return an empty data object since there's nothing to restore with this passthrough.
    return Data()
  }
}

// MARK: - MessageEncryptor

extension PassthroughSecureBLEChannel: MessageEncryptor {
  /// Encrypts the given message.
  ///
  /// This implementation will simply return the same message passed to it.
  ///
  /// - Returns: The given message or `nil` if a secure channel has not been established.
  func encrypt(_ message: Data) throws -> Data {
    guard state == .established else {
      throw PassthroughSecureBLEChannelError.methodsCalledOutOfOrder
    }
    return message
  }

  /// Decrypts the given message.
  ///
  /// This implementation will simply return the same message passed to it.
  ///
  /// - Returns: The given message or `nil` if a secure channel has not been established.
  func decrypt(_ message: Data) throws -> Data {
    guard state == .established else {
      throw PassthroughSecureBLEChannelError.methodsCalledOutOfOrder
    }
    return message
  }
}
