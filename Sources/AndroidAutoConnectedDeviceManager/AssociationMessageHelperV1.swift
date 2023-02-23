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

/// Handles version 1 of the message exchange.
///
/// Phases are:
///   1) Send device ID and receive car ID.
///   2) Establish encryption.
///   3) Complete association.
@MainActor final class AssociationMessageHelperV1 {
  private static let encryptionSetUpParams = MessageStreamParams(
    recipient: Config.defaultRecipientUUID, operationType: .encryptionHandshake)

  static let log = Logger(for: AssociationMessageHelperV1.self)

  private let messageStream: MessageStream
  private let associator: Associator

  /// Possible states of the association process.
  private enum Phase: Equatable {
    case none, idSent, encryptionInProgress, done
  }

  /// Current association phase.
  private var phase = Phase.none

  init(_ associator: Associator, messageStream: MessageStream) {
    self.associator = associator
    self.messageStream = messageStream
  }

  private func sendDeviceId() {
    let deviceId = DeviceIdManager.deviceId
    try? messageStream.writeMessage(
      deviceId.data,
      params: Self.encryptionSetUpParams
    )

    Self.log("Sending device id:", redacting: "\(deviceId.uuidString)")
  }
}

// MARK: - AssociationMessageHelper
extension AssociationMessageHelperV1: AssociationMessageHelper {
  func start() {
    sendDeviceId()
  }

  func handleMessage(_ message: Data, params: MessageStreamParams) {
    switch phase {
    case .idSent:
      guard let carId = try? extractCarId(fromMessage: message) else {
        Self.log.error("The carId cannot be extracted from the message.")
        associator.notifyDelegateOfError(.malformedCarId)
        return
      }
      associator.carId = carId
      associator.establishEncryption(using: messageStream)
      phase = .encryptionInProgress
    case .encryptionInProgress:
      guard isPairingCodeConfirmation(message) else {
        associator.notifyDelegateOfError(.pairingCodeRejected)
        return
      }

      do {
        try associator.notifyPairingCodeAccepted()
        phase = .done
      } catch {
        associator.notifyDelegateOfError(.pairingCodeRejected)
      }
    case .none:
      // Should never get here, no-op.
      Self.log.error("Invalid state of .none encountered")
    case .done:
      // Should never get here, no-op.
      Self.log.error("Invalid state of .done encountered")
    }
  }

  func messageDidSendSuccessfully() {
    if phase == .none {
      Self.log("Device id successfully sent")
      phase = .idSent
    }
  }

  func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken) {
    associator.displayPairingCode(verificationToken.pairingCode)
  }

  func onPairingCodeDisplayed() {}

  func onEncryptionEstablished() {
    guard let carId = associator.carId else {
      Self.log.error(
        "No car id found after secure channel established. Cannot complete association."
      )
      associator.notifyDelegateOfError(.cannotStoreAssociation)
      return
    }

    guard
      let channel = associator.establishSecuredCarChannel(
        forCarId: carId, messageStream: messageStream)
    else {
      associator.notifyDelegateOfError(.cannotStoreAssociation)
      return
    }
    associator.completeAssociation(channel: channel, messageStream: messageStream)
  }
}
