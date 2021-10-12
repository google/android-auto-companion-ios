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

/// Reconnection Helper for security version 2 which implements an authentication mechanism
/// to prevent device identifiers from being shared in the open.
///
/// See go/aae-batmobile-hide-device-ids for details.
@available(iOS 10.0, *)
class ReconnectionHelperV2 {
  /// Tracks the authentication phase of a car.
  /// Phases are:
  ///   1) Car sends a salt plus a truncated HMAC for it.
  ///   2) We verify that the truncated HMAC matches that computed with an associated car's key.
  ///   3) We compute a new challenge salt and append that to the full HMAC from the previous phase.
  ///   4) The car confirms the full HMAC we sent and sends an HMAC for the challenge salt.
  ///   5) We verify the HMAC response against the computed HMAC for the challenge salt.
  private enum Phase {
    /// Initialized with potential cars for reconnection.
    case unresolved(Set<Car>)

    /// The advertisement's truncated HMAC matches the truncated computed HMAC.
    /// The Associated value is the full computed HMAC data.
    case matchedAdvertisementHMAC(Data)

    /// Full HMAC plus new challenge salt sent to the car.
    case saltChallengeSent(Data)

    /// The car has responded with a matching HMAC for the challenge salt.
    case authenticated

    /// The car has responded with a HMAC that does not match for the challenge salt.
    case failed
  }

  /// Length of the salt we should send as a challenge.
  private static let challengeSaltLength = 16

  private static let logger = Logger(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "ReconnectionHelperV2"
  )

  let authenticatorType: CarAuthenticator.Type
  let peripheral: AnyPeripheral
  var car: Car? = nil
  var carId: String? { car?.id }
  var onReadyForHandshake: (() -> Void)?

  private var phase: Phase

  /// Constructs a helper with the associated cars pending the advertisment that will be used for
  /// matching in a later phase.
  ///
  /// This constructor should only be used when the advertisement data is not known up front. This
  /// can happen under any of the following circumstances:
  /// - The peripheral doesn't support advertisement data (e.g. Apple peripherals).
  /// - The advertisement isn't known (e.g. during state restoration).
  ///
  /// See: https://developer.apple.com/documentation/corebluetooth/cbperipheralmanager/1393252-startadvertising
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral for which the reconnection is being attempted.
  ///   - cars: The cars among which we should test for a match against the advertisement.
  ///   - authenticatorType: Authenticator to use.
  /// - Returns: `nil` if none of the cars are successfully matched against the advertisment.
  init(
    peripheral: AnyPeripheral,
    cars: Set<Car>,
    authenticatorType: CarAuthenticator.Type
  ) {
    self.authenticatorType = authenticatorType
    self.peripheral = peripheral

    Self.logger.debug.log("ReconnectionHelper with candidate cars: \(cars)")

    phase = .unresolved(cars)
  }

  /// Constructs a helper by searching among the cars passed for a car whose key authenticates
  /// the advertisement data.
  ///
  /// This constructor should be used when the advertisement data is known up front (i.e. when
  /// it's actually in the peripheral's advertisement) so the matching associated car (if any) can
  /// be determined before connecting to the peripheral.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral for which the reconnection is being attempted.
  ///   - advertismentData: The advertisement data associated with the peripheral discovery.
  ///   - cars: The cars among which we should test for a match against the advertisement.
  ///   - authenticatorType: Authenticator to use.
  /// - Returns: `nil` if none of the cars are successfully matched against the advertisment.
  init?(
    peripheral: AnyPeripheral,
    advertisementData: Data,
    cars: Set<Car>,
    authenticatorType: CarAuthenticator.Type
  ) {
    self.authenticatorType = authenticatorType
    self.peripheral = peripheral

    phase = .unresolved(cars)

    guard let _ = try? prepareForHandshake(withAdvertisementData: advertisementData) else {
      return nil
    }
  }
}

// MARK: - ReconnectionHelper
@available(iOS 10.0, *)
extension ReconnectionHelperV2: ReconnectionHelper {
  /// Security version implemented by this helper.
  var securityVersion: BLEMessageSecurityVersion { .v2 }

  /// Indicates whether advertisement data is needed to begin the handshake.
  var isReadyForHandshake: Bool {
    return carId != nil
  }

  /// Prepare for the handshake with the advertisment data to configure the helper as needed.
  ///
  /// V2 uses the advertisement to match the associated car.
  ///
  /// - Parameter data: The advertisement data.
  /// - Throws: An error if the helper cannot be configured.
  func prepareForHandshake(withAdvertisementData data: Data) throws {
    guard case let .unresolved(cars) = phase else { return }

    // Find an associated car which can authenticate the advertisment data. The match returned
    // contains the matching car and the full HMAC that we computed.
    guard
      let match = authenticatorType.first(among: cars, matchingData: data as Data)
    else {
      Self.logger.log(
        """
        No associated car found to match the applied advertisement data for peripheral: \
        \(peripheral.logName).
        """
      )
      throw CommunicationManagerError.unassociatedCar
    }

    Self.logger.log(
      """
      Connected to device with authentication key for id (\(match.car.id), meaning it is \
      security version 2.
      """
    )

    car = match.car
    phase = .matchedAdvertisementHMAC(match.hmac)

    onReadyForHandshake?()
  }

  /// Begin the reconnection handshake by sending a challenge.
  ///
  /// Generate a new random salt. We package the full HMAC from the advertisement and the new salt
  /// and send the message.
  ///
  /// - Parameter messageStream: Message stream to use for the handshake.
  /// - Throws: An error if sending the message fails or we are in the wrong state.
  func startHandshake(messageStream: MessageStream) throws {
    Self.logger.log(
      """
      Message stream version resolved. Sending challenge salt for peripheral: \
      \(peripheral.logName).
      """
    )

    guard case let .matchedAdvertisementHMAC(hmac) = phase else {
      Self.logger.error.log(
        """
        The advertised truncated HMAC for peripheral: \(peripheral.logName) doesn't match \
        what we computed.
        """
      )
      throw CommunicationManagerError.invalidMessage
    }

    let challengeSalt = authenticatorType.randomSalt(size: Self.challengeSaltLength)
    let response = hmac + challengeSalt

    try messageStream.writeMessage(
      response,
      params: MessageStreamParams(
        recipient: Config.defaultRecipientUUID,
        operationType: .encryptionHandshake
      )
    )

    phase = .saltChallengeSent(challengeSalt)
  }

  /// Handle the message handshake response.
  ///
  /// Extract the HMAC from the message and compare it with the HMAC computed for the salt
  /// challege we sent in the previous handshake message. If they match then the car has been
  /// authenticated successfully and we are done. If not, we throw an error.
  ///
  /// - Parameters:
  ///   - messageStream: Message stream on which the message was received.
  ///   - message: Handshake message containing the HMAC for the challenge salt we sent.
  /// - Returns: Always returns `true`.
  /// - Throws: An error if we are in the wrong state or the challenge authentication fails.
  func handleMessage(messageStream: MessageStream, message: Data) throws -> Bool {
    Self.logger.log(
      "Handling message. Verifying challenge salt HMAC for peripheral: \(peripheral.logName)."
    )

    guard case let .saltChallengeSent(salt) = phase else {
      Self.logger.error.log(
        """
        Wrong phase: \(phase) for peripheral: \(peripheral.logName). \
        Should instead be the saltChallengeSent phase.
        """
      )
      phase = .failed
      throw CommunicationManagerError.invalidMessage
    }

    guard let car = self.car else {
      Self.logger.fault.log(
        """
        The matching car is `nil` for peripheral: \(peripheral.logName) but should have been \
        resolved before starting the handshake.
        """
      )
      throw CommunicationManagerError.invalidMessage
    }

    let authenticator = try authenticatorType.init(carId: car.id)
    guard authenticator.isMatch(challenge: salt, hmac: message) else {
      Self.logger.error.log(
        """
        The challenge salt HMAC for peripheral: \(peripheral.logName) doesn't match what we \
        computed.
        """
      )
      phase = .failed
      throw CommunicationManagerError.invalidMessage
    }

    phase = .authenticated

    Self.logger.log("Authenticated challenge for peripheral: \(peripheral.logName).")
    return true
  }
}