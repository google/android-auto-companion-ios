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

import AndroidAutoLogger

/// Delegate for processing session events.
public protocol TransportSessionDelegate: AnyObject {
  func session(
    _: AnyTransportSession, didDiscover: AnyTransportPeripheral, mode: PeripheralScanMode)

  func session(
    _: AnyTransportSession,
    peripheral: AnyTransportPeripheral,
    didChangeStateTo: PeripheralStatus
  )
}

/// Encapsulates for a single transport, the lifecycle of peripherals including discovery,
/// association and connection.
public class TransportSession<Provider: TransportPeripheralProvider> {
  public typealias Peripheral = Provider.Peripheral

  private let log = Logger(for: TransportSession.self)

  /// Monitor for peripheral discovery.
  private var peripheralDiscoveryMonitor: PeripheralActivityMonitor?

  /// Delegate for handling session events.
  private var delegate: TransportSessionDelegate? = nil

  /// Provider of the transport layer.
  public let provider: Provider

  /// All peripherals.
  @Locked var peripherals: Set<Peripheral> = []

  public var discoveredPeripherals: [Peripheral] {
    peripherals.filter {
      if case .discovered = $0.status {
        return true
      } else {
        return false
      }
    }
  }

  public init(provider: Provider, delegate: TransportSessionDelegate? = nil) {
    self.provider = provider
    self.delegate = delegate
  }

  /// Begin scanning for peripherals.
  ///
  /// - Parameter mode: Scan mode (association or reconnection) for which to scan peripherals.
  public func scanForPeripherals(
    mode: PeripheralScanMode,
    discoveryHandler: @escaping (Peripheral, Peripheral.DiscoveryContext?) -> Void
  ) {
    stopScanningForPeripherals()
    clearDiscoveredPeripherals()

    peripheralDiscoveryMonitor = provider.scanForPeripherals(mode: mode) {
      [weak self] (peripheral, context) in
      guard let self = self else { return }

      self.peripherals.insert(peripheral)
      peripheral.onStatusChange = { state in
        self.onPeripheralStatusChange(peripheral, state: state)
      }
      discoveryHandler(peripheral, context)
      self.delegate?.session(self, didDiscover: peripheral, mode: mode)
    }
  }

  /// Stop scanning for peripherals.
  public func stopScanningForPeripherals() {
    peripheralDiscoveryMonitor?.cancel()
  }

  private func clearDiscoveredPeripherals() {
    peripherals.subtract(Set(discoveredPeripherals))
  }

  private func onPeripheralStatusChange(_ peripheral: Peripheral, state: PeripheralStatus) {
    delegate?.session(self, peripheral: peripheral, didChangeStateTo: state)
  }
}

/// Conformance for any transport session.
public protocol AnyTransportSession {}

/// Specify transport session conformance.
extension TransportSession: AnyTransportSession {}
