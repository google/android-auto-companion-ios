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

/// Helper for handling `AssociationManager` message exchange allowing support for different
/// versions of the association message exchange.
protocol AssociationMessageHelper {
  static var log: Logger { get }

  /// Start the message exchange.
  func start()

  /// Handle the association message exchange between the device and the car.
  ///
  /// - Parameters
  ///   - message: The message to process.
  ///   - params: Contextual info such as operation type and recipient.
  func handleMessage(_ message: Data, params: MessageStreamParams)

  /// Invoked when a message that is requested to have been sent has succeeded.
  func messageDidSendSuccessfully()

  /// The encryption handshake requires verification using either the full verification data to be
  /// verified through a separate out of band channel or the visual pairing code.
  ///
  /// - Parameter verificationToken: Token with data to verify.
  func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken)

  /// The helper is being notified that the pairing code has been displayed.
  func onPairingCodeDisplayed()

  /// The helper is being notified that encryption has been established.
  func onEncryptionEstablished()
}

// MARK: - Common Methods
extension AssociationMessageHelper {
  static var handshakeMessageParams: MessageStreamParams {
    MessageStreamParams(recipient: Config.defaultRecipientUUID, operationType: .encryptionHandshake)
  }

  /// Extract the Car ID from the message.
  ///
  /// - Returns: The car Id extracted from the message.
  /// - Throws: An error if the message does not meet the required form for a valid car Id.
  func extractCarId(fromMessage message: Data) throws -> String {
    let carId = try CBUUID(carId: message).uuidString
    Self.log("Received id from car: \(carId)")
    return carId
  }

  /// Returns `true` if the given message is a confirmation that the pairing code has been
  /// accepted.
  ///
  /// - Parameter message: The message to check
  /// - Returns: `true` if the pairing code has been confirmed.
  func isPairingCodeConfirmation(_ message: Data) -> Bool {
    let valueStr = String(data: message, encoding: .utf8)
    guard valueStr == AssociationManager.pairingCodeConfirmationValue else {
      Self.log.error(
        """
        Received wrong confirmation for pairing code. Expected \
        <\(AssociationManager.pairingCodeConfirmationValue)>, \
        but received <\(valueStr ?? "nil")>
        """
      )
      return false
    }

    return true
  }

  /// Concatenate the device id with the authentication key and send it securely to the car.
  ///
  /// - Parameter keyData Data for the authentication key to send.
  func sendDeviceIdPlusAuthenticationKey(keyData: Data, on messageStream: MessageStream) {
    let deviceId = DeviceIdManager.deviceId
    var payload = deviceId.data
    payload.append(keyData)
    try? messageStream.writeEncryptedMessage(
      payload,
      params: Self.handshakeMessageParams
    )

    Self.log("Sending device id: <\(deviceId.uuidString)> plus authentication key.")
  }
}
