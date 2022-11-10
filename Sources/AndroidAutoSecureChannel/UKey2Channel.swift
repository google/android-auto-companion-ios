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
import AndroidAutoLogger
import AndroidAutoMessageStream
import AndroidAutoUKey2Wrapper
import CoreBluetooth
import Foundation

/// A channel that utilizes UKey2 (go/ukey2) to establish secure communication.
///
/// UKey2 is a Diffie-Hellman based authenticated key exchange protocol.
class UKey2Channel: SecureBLEChannel {
  /// Token used for verification when establishing a UKey2 channel.
  struct VerificationToken: SecurityVerificationToken {
    private static let log = Logger(for: VerificationToken.self)

    /// Length of the visual pairing code.
    private static var pairingCodeLength: Int { UKey2Channel.pairingCodeLength }

    /// Full backing data.
    let data: Data

    /// Human-readable visual pairing code derived from the full data.
    var pairingCode: String {
      // TODO(b/133236104): Remove this when the lib is fixed to respect the pairing code length.
      // Currently, it always returns 32 bytes since ukey2 c++ lib ignores the length parameter
      let digits: [Character] = data.prefix(Self.pairingCodeLength).map {
        Character("\($0 % 10)")
      }
      let code = String(digits)
      Self.log("Generated pairing code: \(code)")
      return code
    }

    init(_ data: Data) {
      self.data = data
    }
  }

  private static let log = Logger(for: UKey2Channel.self)

  /// An info that is prefixed to an HMAC from this phone to a car.
  private static let clientInfoPrefix = Data("CLIENT".utf8)

  /// An info that is prefixed to an HMAC the car to this device.
  private static let serverInfoPrefix = Data("SERVER".utf8)

  /// Salt value for generating new keys when resuming a secure session.
  private static let resumptionSalt = Data("RESUME".utf8)

  /// The length in bytes that the pairing code should be.
  private static let pairingCodeLength = 6

  private static let recipientUUID = UUID(uuidString: "C0667B9C-FB4F-4B88-A5E2-BEB02C939956")!

  /// The configuration parameters when sending a message over the `BLEMessageStream`.
  private static let streamParams = MessageStreamParams(
    recipient: recipientUUID, operationType: .encryptionHandshake)

  private var ukey2 = UKey2Wrapper(role: .initiator)

  /// A key of a previously saved session. If this value is present, then this indicates that a
  /// reestablishment of a session is occurring.
  private var savedSessionKey: Data?

  /// A session key that combines a previously saved session key with an new one. This value is
  /// used to create HMACs to the phone.
  private var combinedSessionKey: Data?

  private(set) var messageStream: MessageStream?

  /// The state of the secure channel.
  private(set) var state: SecureBLEChannelState = .uninitialized

  /// A delegate that will be notified of events within the secure channel.
  weak var delegate: SecureBLEChannelDelegate?

  /// Establishes a secure channel using UKey2 with the given peripheral.
  ///
  /// This method will clear any delegates that are set on the given peripheral. The peripheral's
  /// delegate is safe to set back on the peripheral when a pairing code confirmation is required.
  ///
  /// The caller should ensure that they have set a `delegate` on this secure channel so that they
  /// can be notified when the pairing code should be shown.
  ///
  /// - Parameter messageStream: The stream used to send messages.
  /// - Throws: An generic error or one of type `UKey2ChannelError`.
  func establish(using messageStream: MessageStream) throws {
    // Always use a new UKey2 session for establishment.
    ukey2 = UKey2Wrapper(role: .initiator)

    guard let message = ukey2.nextHandshakeMessage(), ukey2.handshakeState == .inProgress else {
      resetInternalState()
      state = .failed

      let handshakeError = ukey2.lastHandshakeError
      Self.log.error("Init message failed: \(handshakeError)")
      throw SecureBLEChannelError.handshakeMessageGenerationFailed(handshakeError)
    }

    self.messageStream = messageStream
    messageStream.delegate = self

    Self.log("Writing init handshake message.")

    state = .inProgress

    try messageStream.writeMessage(message, params: UKey2Channel.streamParams)
  }

  /// Reestablish a secure channel using the given data of a previously saved session.
  ///
  /// This method will clear any delegates that are set on the given peripheral. The peripheral's
  /// delegate is safe to set back on the peripheral when the session is established.
  ///
  /// The caller should ensure that they have set a `delegate` on this secure channel so that they
  /// can be notified when the pairing code should be shown.
  ///
  /// - Parameters:
  ///   - messageStream: The stream used to send messages.
  ///   - savedSession: A previously established secure connection.
  /// - Throws: An generic error or one of type `UKey2ChannelError`.
  func establish(
    using messageStream: MessageStream,
    withSavedSession savedSession: Data
  ) throws {
    guard let restoredSession = UKey2Wrapper(savedSession: savedSession),
      let uniqueSessionKey = restoredSession.uniqueSessionKey
    else {
      resetInternalState()
      throw SecureBLEChannelError.invalidSavedSession
    }

    savedSessionKey = uniqueSessionKey

    try establish(using: messageStream)
  }

  /// Notifies this channel that the pairing code has been accepted by the user.
  ///
  /// The pairing code should be the one that is passed to a set delegate via its
  /// `secureBLEChannel(_:requiresVerificationOf:for:)` method.
  ///
  /// Upon successful verification, the secure channel will have been set up. The state of this
  /// channel will be updated to `.established`. Then the `encrypt(_:)` and `decrypt(_:)` methods
  /// will be safe to call.
  ///
  /// - Throws: An error if the acceptance of the pairing code has failed.
  func notifyPairingCodeAccepted() throws {
    guard state == .verificationNeeded else {
      Self.log.error("Can't accept pairing code because state is not verification needed")
      throw SecureBLEChannelError.methodCalledOutOfOrder
    }

    guard ukey2.verifyHandshake(), ukey2.handshakeState == .finished else {
      throw SecureBLEChannelError.verificationFailed(ukey2.lastHandshakeError)
    }

    // The presence of a saved session means we are resuming instead. There are additional steps
    // needed to complete the secure channel setup.
    guard savedSessionKey == nil else { return }

    notifySecureSessionEstablished()
  }

  /// Serializes this secure session.
  ///
  /// This method should only be called after the `state` of this session is `.established`.
  ///
  /// - Returns: A serialized version of this UKey2 session.
  /// - Throws: An error if the session cannot be saved.
  func saveSession() throws -> Data {
    guard state == .established else {
      let errorMessage = "Attempting to save session before secure session established"
      throw SecureBLEChannelError.saveSessionFailed(errorMessage)
    }

    guard let savedSession = ukey2.saveSession() else {
      let errorMessage = "Could not save the current session"
      throw SecureBLEChannelError.saveSessionFailed(errorMessage)
    }

    return savedSession
  }

  private func resetInternalState() {
    messageStream = nil
    savedSessionKey = nil

    state = .uninitialized
  }

  private func notifySecureSessionEstablished() {
    guard let messageStream = messageStream else {
      notifyDelegateOfError(SecureBLEChannelError.methodCalledOutOfOrder)
      return
    }

    state = .established

    messageStream.messageEncryptor = self
    delegate?.secureBLEChannel(self, establishedUsing: messageStream)

    self.messageStream = nil
  }

  private func notifyDelegateOfError(_ error: Error) {
    Self.log.error("Error encountered during handshake: \(error.localizedDescription)")

    state = .failed
    delegate?.secureBLEChannel(self, encounteredError: error)
  }

  /// Performs actions based on the given state of `ukey2`.
  private func process(_ state: AAEState) {
    switch state {
    case .inProgress:
      sendNextHandshakeMessage()

    case .verificationNeeded:
      // Note: UKey2 requires `verificationData` actually be called to advance its internal state.
      guard
        let verificationBytes = ukey2.verificationData(
          withByteLength: UKey2Channel.pairingCodeLength
        )
      else {
        notifyDelegateOfError(
          SecureBLEChannelError.pairingCodeGenerationFailed(ukey2.lastHandshakeError))
        return
      }

      processVerificationBytes(verificationBytes)

    case .error:
      notifyDelegateOfError(SecureBLEChannelError.handshakeFailed(ukey2.lastHandshakeError))

    default:
      Self.log.error("Invalid handshake state: \(state.rawValue)")
    }
  }

  private func sendNextHandshakeMessage() {
    // This shouldn't happen because this method is only called after a peripheral and
    // characteristic has been set.
    guard let messageStream = messageStream else {
      Self.log.error("No stream when attempting to process state.")
      notifyDelegateOfError(SecureBLEChannelError.methodCalledOutOfOrder)
      return
    }

    guard let message = ukey2.nextHandshakeMessage() else {
      notifyDelegateOfError(
        SecureBLEChannelError.handshakeMessageGenerationFailed(ukey2.lastHandshakeError))
      return
    }

    Self.log("Sending next handshake message.")

    do {
      try messageStream.writeMessage(message, params: UKey2Channel.streamParams)
    } catch {
      Self.log.error("Cannot send next handshake message: \(error.localizedDescription).")
      notifyDelegateOfError(SecureBLEChannelError.cannotSendMessage)
      return
    }

    // The handshake state is updated after a call to nextHandshakeMessage(). So, need to check
    // if we've progressed to a different state.
    process(ukey2.handshakeState)
  }

  private func processVerificationBytes(_ verificationBytes: Data) {
    state = .verificationNeeded

    // If the session key is present, then this is a session resumption.
    guard savedSessionKey == nil else {
      startSessionResumptionFlow()
      return
    }

    // This shouldn't happen because this method should only be called after `establish()` is
    // called.
    guard let messageStream = messageStream else {
      Self.log.error("No stream when attempting to process verification bytes.")
      notifyDelegateOfError(SecureBLEChannelError.methodCalledOutOfOrder)
      return
    }

    let verificationToken = VerificationToken(verificationBytes)

    delegate?.secureBLEChannel(
      self,
      requiresVerificationOf: verificationToken,
      messageStream: messageStream
    )
  }

  /// Resumes a session for a peripheral that has already established a secure channel.
  ///
  /// See go/d2dsessionresumption for more details on the full flow.
  private func startSessionResumptionFlow() {
    // Step 1: Blindly accept the pairing code.
    do {
      try notifyPairingCodeAccepted()
    } catch {
      notifyDelegateOfError(error)
      return
    }

    state = .resumingSession

    guard let newSessionKey = ukey2.uniqueSessionKey,
      let savedSessionKey = savedSessionKey
    else {
      let errorMessage = "Cannot generate session keys."
      notifyDelegateOfError(SecureBLEChannelError.cannotResumeSession(errorMessage))
      return
    }

    var combinedSessionKey = Data()
    combinedSessionKey.append(savedSessionKey)
    combinedSessionKey.append(newSessionKey)

    self.combinedSessionKey = combinedSessionKey

    // Step 2. Send own HMAC to server to verify.
    sendResumptionHMAC(withCombinedKey: combinedSessionKey)

    // Step 3. Wait for server to respond. This logic is taken care of in `verifyServerHMAC`,
    // which will be called when a message is received from the server.
  }

  private func sendResumptionHMAC(withCombinedKey combinedSessionKey: Data) {
    // This shouldn't happen because the message stream should have been set during resumption.
    guard let messageStream = messageStream else {
      Self.log.error("No stream when attempting to send resumption HMAC.")
      notifyDelegateOfError(SecureBLEChannelError.methodCalledOutOfOrder)
      return
    }

    let resumeHMAC = CryptoOps.hkdf(
      inputKeyMaterial: combinedSessionKey,
      salt: UKey2Channel.resumptionSalt,
      info: UKey2Channel.clientInfoPrefix
    )

    guard resumeHMAC != nil else {
      notifyDelegateOfError(
        SecureBLEChannelError.cannotResumeSession("Cannot generate client resumption message."))
      return
    }

    Self.log("Sending resumption information.")

    do {
      try messageStream.writeMessage(resumeHMAC!, params: UKey2Channel.streamParams)
    } catch {
      Self.log.error(
        "Encountered error sending resumption information: \(error.localizedDescription)")

      notifyDelegateOfError(
        SecureBLEChannelError.cannotResumeSession("Error sending resumption HMAC"))
    }
  }

  /// Verifies that the server message has the correct HMAC.
  ///
  /// This method will take care of notifying the delegate if their message was not correct. If the
  /// HMAC is correct, this method will notify that a secure session has been established.
  ///
  /// - Parameter serverMessage: The message from the server to start the resumption. This message
  ///     should contain the resumption hMAC to verify.
  private func verifyServerHMAC(serverMessage: Data) {
    guard let combinedSessionKey = combinedSessionKey else {
      let errorMessage = "No combined session key generated."
      notifyDelegateOfError(SecureBLEChannelError.cannotResumeSession(errorMessage))
      return
    }

    let resumeHMAC = CryptoOps.hkdf(
      inputKeyMaterial: combinedSessionKey,
      salt: UKey2Channel.resumptionSalt,
      info: UKey2Channel.serverInfoPrefix
    )

    guard serverMessage == resumeHMAC else {
      notifyDelegateOfError(
        SecureBLEChannelError.cannotResumeSession("Cannot match resumption message from server."))
      return
    }

    // This shouldn't happen because the message stream should have been set during resumption.
    guard messageStream != nil else {
      Self.log.error("No stream when attempting to verify server HMAC")
      notifyDelegateOfError(SecureBLEChannelError.methodCalledOutOfOrder)
      return
    }

    Self.log("Session resumption complete. Notifying delegate.")

    notifySecureSessionEstablished()
  }
}

// MARK: - MessageEncryptor

extension UKey2Channel: MessageEncryptor {
  /// Encrypts the given message for sending.
  ///
  /// This method should only be called when a secure channel has been established. That is, the
  /// `state` of this channel should be `.established`.
  ///
  /// - Parameter message: The message to encrypt.
  /// - Returns: The encrypted message.
  /// - Throws: An error if the encryption of the message failed.
  func encrypt(_ message: Data) throws -> Data {
    guard state == .established else {
      Self.log.error("Encryption error caused by out of order method call.")
      throw SecureBLEChannelError.methodCalledOutOfOrder
    }

    guard let encryptedMessage = ukey2.encode(message) else {
      Self.log.error("Encryption error caused by message encoding failure.")
      throw SecureBLEChannelError.encryptionFailed
    }

    return encryptedMessage
  }

  /// Decrypts the given message.
  ///
  /// The given message should be one sent by the peripheral that was passed to
  /// `establish(with:characteristic:)`.
  ///
  /// This method should only be called when a secure channel has been established. That is, the
  /// `state` of this channel should be `.established`.
  ///
  /// - Parameter message: The message to decrypt.
  /// - Returns: The decrypted message.
  /// - Throws: An error if the decryption of the message failed.
  func decrypt(_ message: Data) throws -> Data {
    guard state == .established else {
      Self.log.error("Decryption error caused by out of order method call.")
      throw SecureBLEChannelError.methodCalledOutOfOrder
    }

    guard let decryptedMessage = ukey2.decode(message) else {
      Self.log.error("Decryption error caused by message decoding failure.")
      throw SecureBLEChannelError.decryptionFailed
    }

    return decryptedMessage
  }
}

// MARK: - MessageStreamDelegate

extension UKey2Channel: MessageStreamDelegate {
  func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {
    Self.log.debug("Received message from stream. \(messageStream.readingDebugDescription)")

    // The `OperationType` should only be checked from version 2 onwards.
    if messageStream.version != .passthrough {
      guard params.operationType == .encryptionHandshake else {
        Self.log.error(
          """
          Received message with incorrect operation type \
          (\(String(describing: params.operationType))). Ignoring message.
          """
        )

        notifyDelegateOfError(
          SecureBLEChannelError.parseMessageFailed("Incorrect operation type received from car."))
        return
      }
    }

    if state == .resumingSession {
      verifyServerHMAC(serverMessage: message)
      return
    }

    let response = ukey2.parseHandshakeMessage(message)
    guard response.isSuccessful else {
      notifyDelegateOfError(SecureBLEChannelError.parseMessageFailed(ukey2.lastHandshakeError))
      return
    }

    process(ukey2.handshakeState)
  }

  func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {
    Self.log.error(
      """
      Received error during write. \
      (\(messageStream.writingDebugDescription)) \
      Error: \(error.localizedDescription)
      """
    )

    delegate?.secureBLEChannel(self, encounteredError: error)
    state = .failed

    // TODO(b/129885987): Retry the write.
  }

  func messageStreamDidWriteMessage(_ messageStream: MessageStream, to recipient: UUID) {
    Self.log.debug("Successfully wrote message during state: \(state)")
  }

  func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {
    Self.log.error(
      "Underlying BLEMessageStream encountered unrecoverable error. Notifying delegate")
    notifyDelegateOfError(SecureBLEChannelError.unknown)
  }
}
