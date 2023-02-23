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

/// Handles version 2 through 3 of the message exchange.
///
/// Version 2 and 3 Phases are:
///   1) Establish encryption.
///   2) Send device ID and receive car ID.
///   3) Complete association.
@MainActor final class AssociationMessageHelperV2 {
  static let log = Logger(for: AssociationMessageHelperV2.self)

  private let messageStream: MessageStream
  private let associator: Associator

  /// Possible states of the association process.
  private enum Phase {
    case none
    case encryptionInProgress
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
extension AssociationMessageHelperV2: AssociationMessageHelper {
  func start() {
    phase = .encryptionInProgress
    associator.establishEncryption(using: messageStream)
  }

  func handleMessage(_ message: Data, params: MessageStreamParams) {
    switch phase {
    case .encryptionInProgress:
      Self.log.error("Invalid state of .encryptionInProgress encountered.")
      associator.notifyDelegateOfError(.unknown)
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
    guard phase == .encryptionEstablished else { return }

    Self.log("Device id and authentication key successfully sent.")

    guard
      let carId = associator.carId,
      let channel = associator.establishSecuredCarChannel(
        forCarId: carId, messageStream: messageStream)
    else {
      associator.notifyDelegateOfError(.cannotStoreAssociation)
      return
    }

    associator.completeAssociation(channel: channel, messageStream: messageStream)
    phase = .done
  }

  func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken) {
    associator.displayPairingCode(verificationToken.pairingCode)
  }

  func onPairingCodeDisplayed() {
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
