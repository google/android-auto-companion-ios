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

/// The various states that a secure channel can be in.
public enum SecureBLEChannelState {
  /// A secure channel has not been attempted yet with a peripheral.
  case uninitialized

  /// The setup of a secure channel with a peripheral is currently in progress.
  case inProgress

  /// The secure channel is currently waiting on an explicit user confirmation of a pairing code.
  case verificationNeeded

  /// The secure channel is currently attempting to reestablish secure communication with a
  /// previously established peripheral.
  case resumingSession

  /// A secure channel has been established with a peripheral.
  case established

  /// The setup of a secure channel with a peripheral has failed.
  case failed
}

/// Token used for verification when securing a channel.
public protocol SecurityVerificationToken {
  /// Full backing data.
  var data: Data { get }

  /// Visual pairing code derived from the raw data.
  var pairingCode: String { get }
}

/// The delegate that will be notified of various events during the establishment of a secure
/// channel.
public protocol SecureBLEChannelDelegate: AnyObject {
  /// Invoked when a verification code from the peripheral needs to be verified on device.
  ///
  /// After confirmation of the verification token, notify this secure channel of that event by
  /// calling `notifyPairingCodeAccepted()`.
  ///
  /// - Parameters:
  ///   - secureBLEChannel: The secure channel requiring the pairing code to be confirmed.
  ///   - verificationToken: Token to verify either visually or out of band channel.
  ///   - messageStream: The stream that was used to send messages.
  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    requiresVerificationOf verificationToken: SecurityVerificationToken,
    messageStream: MessageStream
  )

  /// Invoked when a secure channel has been established with the given peripheral.
  ///
  /// The peripheral passed by this method will match the peripheral that was passed to
  /// `establish(with:)`.
  ///
  /// Once established, the `BLEMessageStream` returned can be used to write encrypted messages.
  ///
  /// - Parameter:
  ///   - secureBLEChannel: The secure channel that has been established.
  ///   - messageStream: The stream that can now be used to send encrypted messages.
  func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    establishedUsing messageStream: MessageStream
  )

  /// Invoked when there is an error during the establishment of a secure channel.
  ///
  /// - Parameters:
  ///   - secureBLEChannel: The secure channel that encountered the error.
  ///   - error: The cause of the failure.
  func secureBLEChannel(_ secureBLEChannel: SecureBLEChannel, encounteredError error: Error)
}

/// A channel that supports secure communication between the current device and a given BLE
/// peripheral.
public protocol SecureBLEChannel: AnyObject {
  /// The current state of the secure channel.
  var state: SecureBLEChannelState { get }

  /// A delegate that will be notified of the progress of setting up the secure channel.
  var delegate: SecureBLEChannelDelegate? { get set }

  /// Establishes a secure communication over the given stream.
  ///
  /// This method must be called before any `encrypt` or `decrypt` methods can be used.
  ///
  /// - Parameter messageStream: The stream used to send messages.
  /// - Throws: An error if a secure channel cannot be established.
  func establish(using messageStream: MessageStream) throws

  /// Reestablish a secure session with information of a previously established session.
  ///
  /// The `savedSession` that is passed to this method should be data that was returned by the
  /// `saveSession` method.
  ///
  /// Reestablishing a secure session will not prompt the user to verify a security code, meaning
  /// that calling this method will not call
  /// `secureBLEChannel(_:requiresVerificationOf:messageStream)`. Instead, only
  /// `secureBLEChannel(_:establishedUsing:)` will be called when the connection is established.
  ///
  /// - Parameters:
  ///   - messageStream: The stream used to send messages.
  ///   - savedSession: A previously established secure connection.
  /// - Throws: An error if a secure channel cannot be reestablished.
  func establish(
    using messageStream: MessageStream,
    withSavedSession savedSession: Data
  ) throws

  /// Notifies secure channel that the pairing code has been accepted by the user.
  ///
  /// The pairing code to use is passed to a set `delegate`. It should be displayed to the user and
  /// the user should give an explicit confirmation before this method should be called.
  ///
  /// Calling this method should complete the setup of the secure channel.
  ///
  /// - Throws: An error if the pairing code could not be accepted.
  func notifyPairingCodeAccepted() throws

  /// Serializes this secure session into a `Data` object.
  ///
  /// This method should only be valid to call after a session has been established. That is,
  /// `secureBLEChannel(_:establishedUsing:)` should have been called. The `state` of this session
  /// should also be `.established`.
  ///
  /// - Returns: A serialized version of this secure session.
  /// - Throws: An error if this session cannot be saved.
  func saveSession() throws -> Data
}
