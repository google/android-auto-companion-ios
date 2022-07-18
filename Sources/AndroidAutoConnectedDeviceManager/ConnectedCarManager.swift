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

import CoreBluetooth
import Foundation

/// A manager for discovering and connecting to BLE peripheral devices.
public protocol ConnectedCarManager: AnyObject {
  /// The currently available channels for car communication.
  var securedChannels: [SecuredCarChannel] { get }

  /// Convenience method for retrieving the first `SecuredCarChannel` that can communicate with
  /// the given `Car`.
  ///
  /// - Returns: A `SecuredCarChannel` that can communicate with the given `Car` or
  ///   `nil` if no such channel exists.
  func securedChannel(for car: Car) -> SecuredCarChannel?

  /// Observe when the `state` of the connection manager has changed.
  ///
  /// When the state changes, the closure given to this method is passed this current connection
  /// manager, as well as the new state.
  ///
  /// - Parameter observation: The closure to be executed when the state has changed.
  /// - Returns: A token that can be used to cancel the observation.
  @discardableResult
  func observeStateChange(
    using observation: @escaping (ConnectedCarManager, RadioState) -> Void
  ) -> ObservationHandle

  /// Observe when a device has been connected to this manager.
  ///
  /// When a device is connected, the closure given to this method is passed this current connection
  /// manager, as well as the newly connected device.
  ///
  /// The connected device is guaranteed to be associated.
  ///
  /// - Parameter observation: The closure to be executed when a device has been connected.
  /// - Returns: A token that can be used to cancel the observation.
  @discardableResult
  func observeConnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle

  /// Observe when a secure channel has been set up with a given device.
  ///
  /// When a secure communication has been established, the closure given to this method is passed
  /// this current connection manager and the device. The device is guaranteed to be associated.
  ///
  /// Upon registering for observation, the caller will be notified of all existing secured
  /// channels.
  ///
  /// - Parameter observation: The closure to be executed when a device has securely connected.
  /// - Returns: A token that can be used to cancel the observation.
  @discardableResult
  func observeSecureChannelSetUp(
    using observation: @escaping (ConnectedCarManager, SecuredCarChannel) -> Void
  ) -> ObservationHandle

  /// Observe when a device has been disconnected from this manager.
  ///
  /// When a device is disconnected, the closure given to this method is passed this current
  /// connection manager, as well as the disconnected device.
  ///
  /// - Parameter observation: The closure to be executed when a device is disconnected.
  /// - Returns: A token that can be used to cancel the observation.
  @discardableResult
  func observeDisconnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle

  /// Observe when a car has been dissociated from this manager.
  ///
  /// When a device is dissociated, the closure given to this method is passed this current
  /// connection manager, as well as the dissociated device.
  ///
  /// - Parameter observation: The closure to be executed when a device has dissociated.
  /// - Returns: A token that can be used to cancel the observation.
  @discardableResult
  func observeDissociation(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle
}
