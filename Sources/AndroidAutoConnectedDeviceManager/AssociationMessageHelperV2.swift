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

/// Handles version 2 through 4 of the message exchange.
///
/// Version 2 and 3 Phases are:
///   1) Establish encryption.
///   2) Send device ID and receive car ID.
///   3) Complete association.
///
/// Version 4 Phases are:
///   1) Begin encryption handshake.
///   2) Send verification code for the desired mode (visual pairing or OOB).
///   3) Receive confirmation code.
///   4) Establish encryption.
///   5) Send device ID and receive car ID.
///   6) Complete association.
@available(iOS 10.0, *)
final class AssociationMessageHelperV2 {
  private static let handshakeMessageParams = MessageStreamParams(
    recipient: Config.defaultRecipientUUID, operationType: .encryptionHandshake)

  static let logger = Logger(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "AssociationMessageHelperV2"
  )

  private let messageStream: MessageStream
  private let associator: Associator
  private let sendsVerificationCode: Bool

  /// Possible states of the association process.
  private enum Phase {
    case none
    case encryptionInProgress
    case visualConfirmation
    case encryptionEstablished
    case done
  }

  /// Current association phase.
  private var phase = Phase.none

  init(_ associator: Associator, messageStream: MessageStream, sendsVerificationCode: Bool) {
    self.associator = associator
    self.messageStream = messageStream
    self.sendsVerificationCode = sendsVerificationCode
  }

  /// Concatenate the device id with the authentication key and send it securely to the car.
  ///
  /// - Parameter keyData Data for the authentication key to send.
  private func sendDeviceIdPlusAuthenticationKey(keyData: Data) {
    let deviceId = DeviceIdManager.deviceId
    var payload = deviceId.data
    payload.append(keyData)
    try? messageStream.writeEncryptedMessage(
      payload,
      params: Self.handshakeMessageParams
    )

    Self.logger.log("Sent device id: <\(deviceId.uuidString)> plus authentication key.")
  }
}

// MARK: - AssociationMessageHelper
@available(iOS 10.0, *)
extension AssociationMessageHelperV2: AssociationMessageHelper {
  func start() {
    phase = .encryptionInProgress
    associator.establishEncryption(using: messageStream)
  }

  func handleMessage(_ message: Data, params: MessageStreamParams) {
    switch phase {
    case .encryptionInProgress:
      Self.logger.error.log("Invalid state of .encryptionInProgress encountered.")
      associator.notifyDelegateOfError(.unknown)
    case .visualConfirmation:
      do {
        let code = try VerificationCode(serializedData: message)
        guard code.state == .visualConfirmation else {
          Self.logger.error.log(
            "Expecting visual confirmation, but instead received: \(code.state)")
          associator.notifyDelegateOfError(.unknown)
          return
        }
        try associator.notifyPairingCodeAccepted()
      } catch {
        associator.notifyDelegateOfError(.pairingCodeRejected)
      }
    case .encryptionEstablished:
      guard let carId = try? extractCarId(fromMessage: message) else {
        Self.logger.error.log("Error extracting carId from message.")
        associator.notifyDelegateOfError(.malformedCarId)
        return
      }
      associator.carId = carId

      let authenticator = CarAuthenticatorImpl()
      guard let _ = try? authenticator.saveKey(forIdentifier: carId) else {
        associator.notifyDelegateOfError(.authenticationKeyStorageFailed)
        return
      }

      sendDeviceIdPlusAuthenticationKey(keyData: authenticator.keyData)
      associator.completeAssociation(forCarId: carId, messageStream: messageStream)
      phase = .done
    case .none:
      Self.logger.error.log("Invalid state of .none encountered.")
      associator.notifyDelegateOfError(.unknown)
    case .done:
      Self.logger.error.log("Invalid state of .done encountered.")
      associator.notifyDelegateOfError(.unknown)
    }
  }

  func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken) {
    let shouldDisplayPairingCode: Bool
    if sendsVerificationCode {
      do {
        var code = VerificationCode()
        // TODO(b/191785839): Check for the OOB token and send it if present.
        shouldDisplayPairingCode = true
        code.state = .visualVerification
        phase = .visualConfirmation
        let message = try code.serializedData()
        try messageStream.writeMessage(message, params: Self.handshakeMessageParams)
      } catch {
        Self.logger.error.log("Error sending pairing verification code.")
        associator.notifyDelegateOfError(.verificationCodeFailed)
        return
      }
    } else {
      shouldDisplayPairingCode = true
    }

    guard shouldDisplayPairingCode else { return }
    associator.displayPairingCode(verificationToken.pairingCode)
  }

  func onPairingCodeDisplayed() {
    // If we send the verification code, we only need confirmation from the IHU.
    guard !sendsVerificationCode else { return }

    do {
      try associator.notifyPairingCodeAccepted()
    } catch {
      associator.notifyDelegateOfError(.pairingCodeRejected)
    }
  }

  func onEncryptionEstablished() {
    phase = .encryptionEstablished
  }
}
