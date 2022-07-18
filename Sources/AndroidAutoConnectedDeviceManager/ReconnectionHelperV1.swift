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

/// Reconnection Helper for security version 1 which allows device identifiers to be exchanged
/// in the open.
///
/// This version has been deprecated as a result of the privacy implications. See
/// go/aae-batmobile-device-id-exchange for more details.
class ReconnectionHelperV1 {
  private static let log = Logger(for: ReconnectionHelperV1.self)

  let peripheral: AnyPeripheral
  var carId: String?
  var onReadyForHandshake: (() -> Void)?

  /// Indicates whether this helper is ready for handshake.
  var isReadyForHandshake = true

  /// Initializer for variant where the carId comes in a later message.
  init(peripheral: AnyPeripheral) {
    self.peripheral = peripheral
  }
}

// MARK: - ReconnectionHelper
extension ReconnectionHelperV1: ReconnectionHelper {
  func discoveryUUID(from config: UUIDConfig) -> CBUUID {
    config.reconnectionUUID(for: .v1)
  }

  /// Prepare for the handshake with the advertisement data to configure the helper as needed.
  ///
  /// For V1, this is a NO-OP because it's ready for the handshake upon completing initialization.
  ///
  /// - Parameter data: The advertisement data.
  /// - Throws: An error if the helper cannot be configured.
  func prepareForHandshake(withAdvertisementData data: Data) {
    // NO-OP because V1 is already ready for the reconnection handshake.
  }

  /// Handle the security version resolution.
  func onResolvedSecurityVersion(_ version: MessageSecurityVersion) throws {
    guard version == .v1 else {
      Self.log.error("Resolved mismatched security version: \(version)")
      throw CommunicationManagerError.mismatchedSecurityVersion
    }
  }

  /// Begin the reconnection handshake by sending the device id.
  ///
  /// - Parameter messageStream: Message stream to use for the handshake.
  /// - Throws: An error if sending the message fails.
  func startHandshake(messageStream: MessageStream) throws {
    Self.log(
      "Begin reconnection handshake. Sending device id to car.",
      redacting: "id: (\(DeviceIdManager.deviceId))"
    )

    try messageStream.writeMessage(
      DeviceIdManager.deviceId.data,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )
  }

  /// Extracts the carId from the message which completes the handshake.
  ///
  /// - Parameters:
  ///   - messageStream: Message stream on which the message was received.
  ///   - message: Handshake message containing the car id.
  /// - Returns: Always returns `true`.
  /// - Throws: An error if the message does not meet the required form for a valid car Id.
  func handleMessage(messageStream: MessageStream, message: Data) throws -> Bool {
    // Extract the carId from the message.
    let carId = try CBUUID(carId: message).uuidString
    self.carId = carId
    Self.log("Received device id from car.", redacting: "carId: \(carId)")
    return true
  }

  func configureSecureChannel(
    _: SecuredConnectedDeviceChannel,
    using connectionHandle: ConnectionHandle,
    completion: (Bool) -> Void
  ) {
    // No additional configuration needed, so we can indicate completion immediately.
    completion(true)
  }
}
