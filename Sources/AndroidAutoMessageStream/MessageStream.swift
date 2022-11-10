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

import AndroidAutoConnectedDeviceTransport
import Foundation

/// Delegate to be notified of message stream events.
public protocol MessageStreamDelegate: AnyObject {
  /// Called when the read characteristic has updated its value.
  ///
  /// This method will be called when a complete message has been received from the characteristic.
  /// Note that the `message` parameter might be different than the `value` field of the
  /// characteristic as the latter may only represent part of a message.
  ///
  /// If the message received from the read characteristic was encrypted, there needs to be a
  /// `messageEncryptor` set on the `BLEMessageStream` to perform the decryption. If not, then
  /// `messageStream(_:didEncounterUpdateError)` will be invoked instead.
  ///
  /// - Parameters:
  ///   - messageStream: The stream that is monitoring characteristic notifications.
  ///   - message: The complete message from the characteristic.
  ///   - params: The contextual metadata for the received message.
  func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  )

  /// Called when a write of a complete message to the write characteristic has failed.
  ///
  /// - Parameters:
  ///   - messageStream: The stream that is handling writing.
  ///   - error: The error that occurred.
  ///   - recipient: The unique identifier for the receiver of the message.
  func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  )

  /// Called when the write of a complete message has succeeded.
  ///
  /// - Parameters:
  ///   - messageStream: The stream that is handling writing.
  ///   - recipient: The unique identifier for the receiver of the message.
  func messageStreamDidWriteMessage(_ messageStream: MessageStream, to recipient: UUID)

  /// Called when this stream has encountered an unrecoverable error.
  ///
  /// When this method has been invoked, this stream should not be used anymore for sending or
  /// receiving messages. It should instead be discarded and a new stream set up.
  ///
  /// - Parameter messageStream: The stream that encountered the error.
  func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream)
}

/// Handles the streaming of BLE messages to a specific peripheral.
///
/// This stream will handle if messages to a particular peripheral need to be split into
/// multiple messages or if the messages can be sent all at once. Internally, it will have its own
/// protocol for how the split messages are structured.
public protocol MessageStream: AnyObject {
  /// The version of this stream.
  var version: MessageStreamVersion { get }

  /// The peripheral to send messages to.
  var peripheral: AnyTransportPeripheral { get }

  /// Indicates whether this stream is valid for reading and writing.
  var isValid: Bool { get }

  /// Debug description for reading.
  var readingDebugDescription: String { get }

  /// Debug description for writing.
  var writingDebugDescription: String { get }

  /// A delegate that will be notified of events.
  var delegate: MessageStreamDelegate? { get set }

  /// The encryptor responsible for encrypting and decrypting messages.
  var messageEncryptor: MessageEncryptor? { get set }

  /// Writes the given message to the remote peripheral associated with this stream.
  ///
  /// Upon completion of the write, a set `delegate` will be notified via a call to
  /// `messageStreamDidWriteMessage`.
  ///
  /// - Parameters:
  ///   - message: The message to write.
  ///   - params: The configuration parameters for the write.
  func writeMessage(_ message: Data, params: MessageStreamParams) throws

  /// Encrypts and writes the given message to the remote peripheral associated with this stream.
  ///
  /// Upon completion of the write, a set `delegate` will be notified via a call to
  /// `messageStreamDidWriteMessage`.
  ///
  /// For a message to be encrypted, it is expected that a valid `messageEncryptor` has been set on
  /// this stream.
  ///
  /// - Parameter message: The message to write.
  /// - Throws: An error if the message cannot be encrypted.
  func writeEncryptedMessage(_ message: Data, params: MessageStreamParams) throws
}
