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

@_implementationOnly import AndroidAutoMessageStream
import CoreBluetooth
import Foundation

/// Protocol implemented by helpers which manage the reconnection handshake.
protocol ReconnectionHelper: AnyObject {
  /// The peripheral for which reconnection is being attempted.
  var peripheral: AnyPeripheral { get }

  /// The car id should be determined during the handshake. If the car id is `nil` after the
  /// handshake has completed, it implies a failure occurred during the handshake.
  var carId: String? { get }

  /// Indicates whether this helper is ready for handshake.
  var isReadyForHandshake: Bool { get }

  /// Completion handler to call when ready for handshake.
  var onReadyForHandshake: (() -> Void)? { get set }

  /// Get the appropriate discovery uuid from the config.
  func discoveryUUID(from config: UUIDConfig) -> CBUUID

  /// Prepare for the handshake with the advertisement data to configure the helper as needed.
  ///
  /// - Parameter data: The advertisement data.
  /// - Throws: An error if the helper cannot be configured.
  func prepareForHandshake(withAdvertisementData data: Data) throws

  /// Handle the security version resolution.
  ///
  /// A helper is associated with specific security versions, and the helper is instantiated
  /// based on the advertisement before the security version is resolved. This method is called
  /// when the security version has been resolved.
  ///
  /// - Parameter version: The resolved security version.
  /// - Throws: An error if the resolved security version is inconsistent with the helper.
  func onResolvedSecurityVersion(_ version: MessageSecurityVersion) throws

  /// Start the reconnection handshake.
  ///
  /// - Parameter messageStream: Message stream to use for the handshake.
  /// - Throws: An error if something goes wrong with the handshake.
  func startHandshake(messageStream: MessageStream) throws

  /// Process a handshake message.
  ///
  /// - Parameters:
  ///   - messageStream: Message stream on which the message was received.
  ///   - message: Handshake message to process.
  /// - Returns: `true` if the handshake has completed.
  /// - Throws: An error if the message does not match what is expected.
  func handleMessage(messageStream: MessageStream, message: Data) throws -> Bool

  /// Configure the secure channel using the specified connection handle and call completion when
  /// done.
  ///
  /// - Parameters:
  ///   - channel: Channel to configure.
  ///   - connectionHandle: Handles the configuration request.
  ///   - completion: Handler to call upon configuration completion passing boolean for success.
  func configureSecureChannel(
    _ channel: SecuredConnectedDeviceChannel,
    using connectionHandle: ConnectionHandle,
    completion: @escaping (Bool) -> Void
  )
}
