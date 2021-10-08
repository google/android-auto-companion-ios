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

import Foundation

/// The possible errors that can occur during the establishment of a secure channel.
public enum SecureBLEChannelError: Error, Equatable {
  /// An unknown error has occurred and a secure channel cannot be established.
  case unknown

  /// The generation of handshake messages necessary to set up the secure channel has failed.
  case handshakeMessageGenerationFailed(String)

  /// This secure channel has received an empty response from the peripheral it is attempting to
  /// establish a secure channel with.
  case receivedEmptyHandshakeMessage

  /// The method that was invoked was not called in the correct order.
  case methodCalledOutOfOrder

  /// An error occurred during the sending of handshake messages to the remote peripheral.
  case cannotSendMessage

  /// Parsing of a message from a remote peripheral has failed.
  case parseMessageFailed(String)

  /// The generation of a pairing code to display to the user has failed.
  case pairingCodeGenerationFailed(String)

  /// This secure channel has failed to verify the pairing code.
  case verificationFailed(String)

  /// The establishment of a secure channel has failed.
  case handshakeFailed(String)

  /// The encryption of a given message has failed.
  case encryptionFailed

  /// The decryption of a given message has failed.
  case decryptionFailed

  /// Saving the information about the current saved session has failed.
  case saveSessionFailed(String)

  /// The saved session to restore from is invalid.
  case invalidSavedSession

  /// An error occurred during session resumption.
  case cannotResumeSession(String)
}

/// An extension of the error that sets a message describing the cause.
extension SecureBLEChannelError: LocalizedError {
  public var errorDescription: String? {
    // Simply return the error message passed because UKey2 generates its own error messages.
    switch self {
    case .unknown:
      return "An unknown error has occurred and a secure channel cannot be established."
    case .handshakeMessageGenerationFailed(let errorMessage):
      return errorMessage
    case .receivedEmptyHandshakeMessage:
      return "Received empty handshake message from responder."
    case .methodCalledOutOfOrder:
      return "Invoked method not called in the correct order."
    case .cannotSendMessage:
      return "An error occurred during the sending of a message to the remote peripheral."
    case .parseMessageFailed(let errorMessage):
      return errorMessage
    case .pairingCodeGenerationFailed(let errorMessage):
      return errorMessage
    case .verificationFailed(let errorMessage):
      return errorMessage
    case .handshakeFailed(let errorMessage):
      return errorMessage
    case .encryptionFailed:
      return "Could not encrypt the given message."
    case .decryptionFailed:
      return "Could not decrypt the given message."
    case .saveSessionFailed(let errorMessage):
      return errorMessage
    case .invalidSavedSession:
      return "The saved session to restore from is invalid."
    case .cannotResumeSession(let errorMessage):
      return errorMessage
    }
  }
}
