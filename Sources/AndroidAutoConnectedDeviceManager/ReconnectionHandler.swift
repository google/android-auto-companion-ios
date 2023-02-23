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

@_implementationOnly import AndroidAutoConnectedDeviceTransport
@_implementationOnly import AndroidAutoCoreBluetoothProtocols
@_implementationOnly import AndroidAutoMessageStream
import Foundation

/// The possible errors that can result from setting up encryption.
enum ReconnectionHandlerError: Error {
  /// There was an error with reestablishing encryption.
  case cannotEstablishEncryption

  /// The car has sent an invalid message during the handshake.
  case invalidMessageFromCar

  /// Cannot read a message sent by the car.
  case cannotParseMessage
}

/// A delegate to be notified when a secure channel has been set up.
@MainActor protocol ReconnectionHandlerDelegate: AnyObject {
  /// Invoked when a secure channel has been established.
  ///
  /// After this call, `writeEncryptedMessage` can be called without an error being thrown.
  ///
  /// - Parameters
  ///   - reconnectionHandler: The handler established encryption.
  ///   - securedCarChannel: The established secure channel for sending and receiving messages.
  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  )

  /// Called when there was an error during a secure channel establishment.
  ///
  /// - Parameters:
  ///   - reconnectionHandler: The handler attempting a secure connection.
  ///   - error: The error that occurred.
  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEncounterError error: ReconnectionHandlerError
  )
}

/// A handler that is able to establish a secure session based off of previously stored encryption
/// keys.
@MainActor protocol ReconnectionHandler {
  /// The car that is being connected with.
  var car: Car { get }

  /// The underlying peripheral that represents the car being connected to.
  var peripheral: BLEPeripheral { get }

  /// The delegate to be notified of the status of encryption setup.
  var delegate: ReconnectionHandlerDelegate? { get set }

  /// Starts the process of initializing a secure channel.
  ///
  /// Once completed, the `delegate` set on this class will be notified.
  /// - Throws: An error if encryption cannot be established.
  func establishEncryption() throws
}

/// A channel that also exposes its backing peripheral.
@MainActor protocol SecuredCarChannelPeripheral {
  /// The underlying peripheral that this channel provides secure communication with.
  var peripheral: AnyTransportPeripheral { get }
}
