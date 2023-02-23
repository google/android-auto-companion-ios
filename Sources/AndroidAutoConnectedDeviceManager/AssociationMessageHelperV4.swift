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

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import AndroidAutoLogger
@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation
@_implementationOnly import AndroidAutoCompanionProtos

private typealias VerificationCodeState = Com_Google_Companionprotos_VerificationCodeState
private typealias VerificationCode = Com_Google_Companionprotos_VerificationCode

/// Handles version 4 of the message exchange.
///
/// Version 4 Phases are:
///   1) Begin encryption handshake.
///   2) Send verification code for the desired mode (visual pairing or OOB).
///   3) Receive confirmation code.
///   4) Establish encryption.
///   5) Send device ID and receive car ID.
///   6) Complete association.
@MainActor final class AssociationMessageHelperV4 {
  static let log = Logger(for: AssociationMessageHelperV4.self)

  private let messageStream: MessageStream
  private let associator: Associator

  /// Possible states of the association process.
  private enum Phase {
    case none
    case encryptionInProgress
    case visualConfirmation
    case outOfBandConfirmation(SecurityVerificationToken, OutOfBandToken)
    case encryptionEstablished
    case done
  }

  /// Current association phase.
  private var phase = Phase.none

  init(_ associator: Associator, messageStream: MessageStream) {
    self.associator = associator
    self.messageStream = messageStream
  }
}

// MARK: - AssociationMessageHelper
extension AssociationMessageHelperV4: AssociationMessageHelper {
  func start() {
    phase = .encryptionInProgress
    associator.establishEncryption(using: messageStream)
  }

  func handleMessage(_ message: Data, params: MessageStreamParams) {
    switch phase {
    case .encryptionInProgress:
      Self.log.error("Invalid state of .encryptionInProgress encountered.")
      associator.notifyDelegateOfError(.unknown)
    case .visualConfirmation:
      do {
        let code = try VerificationCode(serializedData: message)
        guard code.state == .visualConfirmation else {
          Self.log.error("Expecting visual confirmation, but instead received: \(code.state)")
          associator.notifyDelegateOfError(.unknown)
          return
        }
        try associator.notifyPairingCodeAccepted()
      } catch {
        associator.notifyDelegateOfError(.pairingCodeRejected)
      }
    case let .outOfBandConfirmation(securityToken, outOfBandToken):
      do {
        let code = try VerificationCode(serializedData: message)
        guard code.state == .oobVerification else {
          Self.log.error("Expecting Out-Of-Band confirmation, but instead received: \(code.state)")
          associator.notifyDelegateOfError(.unknown)
          return
        }

        let confirmation = try outOfBandToken.decrypt(code.payload)
        guard confirmation == securityToken.data else {
          Self.log.error("Decrypted pairing verification code does not match the security token.")
          associator.notifyDelegateOfError(.pairingCodeRejected)
          return
        }
        try associator.notifyPairingCodeAccepted()
      } catch {
        associator.notifyDelegateOfError(.pairingCodeRejected)
      }
    case .encryptionEstablished:
      guard let carId = try? extractCarId(fromMessage: message) else {
        Self.log.error("Error extracting carId from message.")
        associator.notifyDelegateOfError(.malformedCarId)
        return
      }
      associator.carId = carId

      let authenticator = CarAuthenticatorImpl()
      guard let _ = try? authenticator.saveKey(forIdentifier: carId) else {
        associator.notifyDelegateOfError(.authenticationKeyStorageFailed)
        return
      }

      sendDeviceIdPlusAuthenticationKey(keyData: authenticator.keyData, on: messageStream)
    case .none:
      Self.log.error("Invalid state of .none encountered.")
      associator.notifyDelegateOfError(.unknown)
    case .done:
      Self.log.error("Invalid state of .done encountered.")
      associator.notifyDelegateOfError(.unknown)
    }
  }

  func messageDidSendSuccessfully() {
    guard case .encryptionEstablished = phase else { return }

    Self.log("Device id and authentication key successfully sent.")

    guard
      let carId = associator.carId,
      let channel = associator.establishSecuredCarChannel(
        forCarId: carId, messageStream: messageStream)
    else {
      associator.notifyDelegateOfError(.cannotStoreAssociation)
      return
    }

    associator.connectionHandle.requestConfiguration(for: channel) { [weak self] in
      guard let self = self else { return }
      Self.log("Channel user role: \(channel.userRole.debugDescription)")
      self.associator.completeAssociation(channel: channel, messageStream: self.messageStream)
      self.phase = .done
    }
  }

  func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken) {
    Self.log("Helper requesting out of band token.")
    associator.requestOutOfBandToken { [weak self] outOfBandToken in
      guard let self = self else { return }
      do {
        var code = VerificationCode()
        if let outOfBandToken = outOfBandToken {
          Self.log("Out of band verification token will be used.")
          code.state = .oobVerification
          code.payload = try outOfBandToken.encrypt(verificationToken.data)
          self.phase = .outOfBandConfirmation(verificationToken, outOfBandToken)
        } else {
          Self.log("No out of band verification token. Will perform visual verification.")
          code.state = .visualVerification
          self.phase = .visualConfirmation
          self.associator.displayPairingCode(verificationToken.pairingCode)
        }

        let message = try code.serializedData()
        try self.messageStream.writeMessage(message, params: Self.handshakeMessageParams)
      } catch {
        Self.log.error("Error sending pairing verification code.")
        self.associator.notifyDelegateOfError(.verificationCodeFailed)
        return
      }
    }
  }

  func onPairingCodeDisplayed() {
    // Nothing to do here as we await confirmation from the IHU.
  }

  func onEncryptionEstablished() {
    phase = .encryptionEstablished
  }
}
