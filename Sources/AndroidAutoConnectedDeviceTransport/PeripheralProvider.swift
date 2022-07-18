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
import Foundation

/// Conformance for the peripheral provider of a specific transport.
///
/// Allows scanning for associated and unassociated peripherals available through the specific
/// transport.
public protocol TransportPeripheralProvider: AnyObject {
  associatedtype Peripheral

  associatedtype DiscoveryMonitor: SomePeripheralDiscoveryMonitor
  where DiscoveryMonitor.Peripheral == Peripheral

  /// Indicates whether this provider is ready to process peripheral actions (e.g. scans).
  var isReady: Bool { get }

  /// State of the provider's radio.
  var radioState: TransportRadioState { get }

  /// The monitor receiving discovered peripherals.
  var discoveryMonitor: DiscoveryMonitor? { get set }

  /// Start scanning in the specified mode.
  ///
  /// - Parameter mode: The scan mode to use when discovering peripherals.
  /// - Returns: `true` if the scan successfully began and `false` if not.
  @discardableResult
  func startPeripheralScan(mode: PeripheralScanMode) -> Bool

  /// Stop scanning for peripherals.
  func stopPeripheralScan()

  /// Request to connect the peripheral.
  ///
  /// - Parameter peripheral: The peripheral to connect.
  func requestConnection(_: Peripheral)

  /// Cancel any request for connecting to the specified peripheral and disconnect if connected.
  ///
  /// - Parameter peripheral: The peripheral for which to cancel connections.
  func cancelConnection(_: Peripheral)
}

// MARK: - Default Implementations

/// Provide default implementations.
extension TransportPeripheralProvider {
  /// By default, the provider is ready if it is powered on.
  public var isReady: Bool { radioState.isPoweredOn }

  /// Begin scanning for either associated or unassociated peripherals.
  ///
  /// Cancels any previous discovery monitor, creates a new discovery monitor and calls
  /// `startPeripheralScan(mode: mode)`.
  ///
  /// - Parameters:
  ///   - mode: Scan mode for association or reconnection.
  ///   - discoveryHandler: Processes each discovered peripheral.
  /// - Returns: A monitor for controlling the scanner.
  public func scanForPeripherals(
    mode: PeripheralScanMode,
    discoveryHandler: @escaping (Peripheral, Peripheral.DiscoveryContext?) -> Void
  ) -> PeripheralActivityMonitor {
    discoveryMonitor?.cancel()
    let monitor = DiscoveryMonitor(mode: mode, discoveryHandler: discoveryHandler) { [weak self] in
      self?.discoveryMonitor = nil
      self?.stopPeripheralScan()
    }
    discoveryMonitor = monitor

    let success = startPeripheralScan(mode: mode)

    if !success {
      Logger(for: type(of: self)).error(
        """
        Request to scan for cars to associate, but this peripheral provider is not ready. \
        Will begin scan when possible.
        """
      )
    }

    return monitor
  }

  /// Begin scanning based on the last specified discovery monitor.
  ///
  /// Checks whether there is an active discovery monitor and the provider is ready. If these
  /// conditions are satisfied, the scan will start. This can be used to automatically begin scans
  /// when the provider becomes ready.
  public func startScanIfNeeded() {
    guard isReady, let monitor = discoveryMonitor else { return }

    startPeripheralScan(mode: monitor.mode)
  }
}

/// Activity monitor for peripheral discovery.
public protocol SomePeripheralDiscoveryMonitor: PeripheralActivityMonitor {
  associatedtype Peripheral: TransportPeripheral

  /// Mode for which to scan peripherals.
  var mode: PeripheralScanMode { get }

  /// Required initializer for creating a monitor.
  ///
  /// - Parameters:
  ///   - mode: Scan mode (e.g. association or reconnection).
  ///   - discoveryHandler: Handler to call when a peripheral is discovered with context.
  ///   - cancelHandler: Handler to call when this monitor is canceled.
  init(
    mode: PeripheralScanMode,
    discoveryHandler: @escaping (Peripheral, Peripheral.DiscoveryContext?) -> Void,
    cancelHandler: @escaping () -> Void
  )
}

/// Mode (i.e. association or reconnection) for which to scan peripherals.
public enum PeripheralScanMode: Equatable {
  /// Scanning for unassociated peripherals to associate.
  case association

  /// Scanning for associated peripherals to reconnect.
  case reconnection

  /// Convenience for determining if for association.
  public var isAssociation: Bool { self == .association }

  /// Convenience for determining if for reconnection.
  public var isReconnection: Bool { self == .reconnection }
}
