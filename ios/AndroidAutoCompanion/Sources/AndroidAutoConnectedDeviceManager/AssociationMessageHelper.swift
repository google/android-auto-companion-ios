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
@available(iOS 10.0, *)
protocol AssociationMessageHelper {
  static var logger: Logger { get }

  /// Start the message exchange.
  func start()

  /// Handle the association message exchange between the device and the car.
  ///
  /// - Parameters
  ///   - message: The message to process.
  ///   - params: Contextual info such as operation type and recipient.
  func handleMessage(_ message: Data, params: MessageStreamParams)

  /// The helper is being notified that the pairing code has been displayed.
  func onPairingCodeDisplayed()

  /// The helper is being notified that encryption has been established.
  func onEncryptionEstablished()
}

// MARK: - Common Methods
@available(iOS 10.0, *)
extension AssociationMessageHelper {
  /// Extract the Car ID from the message.
  ///
  /// - Returns: The car Id extracted from the message.
  /// - Throws: An error if the message does not meet the required form for a valid car Id.
  func extractCarId(fromMessage message: Data) throws -> String {
    let carId = try CBUUID(carId: message).uuidString
    Self.logger.log("Received id from car: \(carId)")
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
      Self.logger.error.log(
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
}
