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

import AndroidAutoCoreBluetoothProtocolsMocks
import CoreBluetooth
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A mock manager that can manually trigger observations.
@MainActor public class ConnectedCarManagerMock: NSObject {
  private var observations = (
    state: [UUID: (ConnectedCarManager, RadioState) -> Void](),
    connected: [UUID: (ConnectedCarManager, Car) -> Void](),
    securedChannel: [UUID: (ConnectedCarManager, SecuredCarChannel) -> Void](),
    disconnected: [UUID: (ConnectedCarManager, Car) -> Void](),
    dissociation: [UUID: (ConnectedCarManager, Car) -> Void]()
  )

  public var securedChannels: [SecuredCarChannel] = []

  public func triggerConnection(for car: Car) {
    observations.connected.values.forEach { observation in
      observation(self, car)
    }
  }

  public func triggerSecureChannelSetUp(with channel: SecuredCarChannel) {
    securedChannels.append(channel)

    observations.securedChannel.values.forEach { observation in
      observation(self, channel)
    }
  }

  public func triggerDissociation(for car: Car) {
    securedChannels.removeAll(where: { $0.car == car })

    observations.dissociation.values.forEach { observation in
      observation(self, car)
    }
  }

  public func triggerDisconnection(for car: Car) {
    securedChannels.removeAll(where: { $0.car == car })

    observations.disconnected.values.forEach { observation in
      observation(self, car)
    }
  }
}

extension ConnectedCarManagerMock: ConnectedCarManager {
  public func securedChannel(for car: Car) -> SecuredCarChannel? {
    return securedChannels.first(where: { $0.car.id == car.id })
  }

  @discardableResult
  public func observeSecureChannelSetUp(
    using observation: @escaping (ConnectedCarManager, SecuredCarChannel) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.securedChannel[id] = observation

    // When first called, notify the observer of all existing secure channels.
    securedChannels.forEach { observation(self, $0) }

    return ObservationHandle { [weak self] in
      self?.observations.securedChannel.removeValue(forKey: id)
    }
  }

  @discardableResult
  public func observeStateChange(
    using observation: @escaping (ConnectedCarManager, RadioState) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.state[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.state.removeValue(forKey: id)
    }
  }

  @discardableResult
  public func observeConnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.connected[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.connected.removeValue(forKey: id)
    }
  }

  @discardableResult
  public func observeDisconnection(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.disconnected[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.disconnected.removeValue(forKey: id)
    }
  }

  @discardableResult
  public func observeDissociation(
    using observation: @escaping (ConnectedCarManager, Car) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    observations.dissociation[id] = observation

    return ObservationHandle { [weak self] in
      self?.observations.dissociation.removeValue(forKey: id)
    }
  }

  public func reset() {
    observations.state.removeAll()
    observations.connected.removeAll()
    observations.securedChannel.removeAll()
    observations.disconnected.removeAll()
  }
}
