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
import Foundation

/// A car that can be used to send encrypted messages.
@MainActor class ReconnectionHandlerImpl: NSObject, ReconnectionHandler {
  private static let log = Logger(for: ReconnectionHandlerImpl.self)

  let messageStream: BLEMessageStream

  private let connectionHandle: ConnectionHandle
  private let secureSession: Data
  private let secureBLEChannel: SecureBLEChannel
  private let secureSessionManager: SecureSessionManager

  /// Possible unlock states.
  enum State {
    /// A setup of a secure channel has not been requested.
    case none

    /// New keys for encryption are being derived.
    case keyExchangeInProgress

    /// A secure connection has been set up and messages can now be writeEncryptedMessage.
    case authenticationEstablished

    /// The channel is in an error state resulting from a failed secure channel establishment.
    case error
  }

  var state = State.none

  weak var delegate: ReconnectionHandlerDelegate?

  let car: Car

  var peripheral: BLEPeripheral {
    return messageStream.peripheral
  }

  /// Initializes this car with all the signals it needs to establish a secure channel.
  ///
  /// - Parameters:
  ///   - car: The car to communicate securely with.
  ///   - connectionHandle: A handle for managing connections to remote cars.
  ///   - secureSession: The data that represents a previous secure session with the car.
  ///   - messageStream: The stream that will handle sending of messages.
  ///   - secureBLEChannel: A secure channel that can encrypt messages.
  ///   - secureSessionManager: Manager for retrieving and storing secure sessions.
  init(
    car: Car,
    connectionHandle: ConnectionHandle,
    secureSession: Data,
    messageStream: BLEMessageStream,
    secureBLEChannel: SecureBLEChannel,
    secureSessionManager: SecureSessionManager
  ) {
    self.car = car
    self.connectionHandle = connectionHandle
    self.secureSession = secureSession
    self.secureBLEChannel = secureBLEChannel
    self.messageStream = messageStream
    self.secureSessionManager = secureSessionManager

    // `init()` needs to be called before `self` can be used for purposes other than referencing
    // fields.
    super.init()
    secureBLEChannel.delegate = self
  }

  func establishEncryption() throws {
    Self.log("Starting setup of secure channel with car (id: \(car.id)).")

    state = .keyExchangeInProgress

    try secureBLEChannel.establish(
      using: messageStream,
      withSavedSession: secureSession
    )
  }
}

// MARK: - SecureBLEChannelDelegate

extension ReconnectionHandlerImpl: SecureBLEChannelDelegate {
  public func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    requiresVerificationOf verificationToken: SecurityVerificationToken,
    messageStream: MessageStream
  ) {
    // Since we're resuming a session, this method should never be called.
    Self.log.error(
      "Received unexpected request to show PIN. Was establish() called with a saved session?")

    state = .error

    delegate?.reconnectionHandler(self, didEncounterError: .cannotEstablishEncryption)
  }

  public func secureBLEChannel(
    _ secureBLEChannel: SecureBLEChannel,
    establishedUsing messageStream: MessageStream
  ) {
    // Update the saved secure session for this new one.
    guard let secureSession = try? secureBLEChannel.saveSession(),
      secureSessionManager.storeSecureSession(secureSession, for: car.id)
    else {
      Self.log.error("Cannot save the secure session")

      state = .error
      delegate?.reconnectionHandler(self, didEncounterError: .cannotEstablishEncryption)
      return
    }

    state = .authenticationEstablished

    let securedCarChannel = EstablishedCarChannel(
      car: car,
      connectionHandle: connectionHandle,
      messageStream: messageStream
    )

    delegate?.reconnectionHandler(self, didEstablishSecureChannel: securedCarChannel)
  }

  public func secureBLEChannel(_ secureBLEChannel: SecureBLEChannel, encounteredError error: Error)
  {
    // TODO(b/133505558): Define error states if unlock cannot be done.
    Self.log.error("Error during session resumption: \(error.localizedDescription)")

    state = .error

    delegate?.reconnectionHandler(self, didEncounterError: .cannotEstablishEncryption)
  }
}
