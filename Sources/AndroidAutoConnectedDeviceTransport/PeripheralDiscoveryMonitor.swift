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

/// Generic implementation of `SomePeripheralDiscoveryMonitor`.
public class PeripheralDiscoveryMonitor<Peripheral: TransportPeripheral>:
  SomePeripheralDiscoveryMonitor
{
  public typealias DiscoveryContext = Peripheral.DiscoveryContext

  /// Mode (e.g. association or reconnection) for discovery.
  public var mode: PeripheralScanMode

  /// Handler to call when a peripheral is discovered.
  private var discoveryHandler: (Peripheral, DiscoveryContext?) -> Void

  /// Handler to call when the monitor is canceled.
  private var cancelHandler: () -> Void

  /// Initializer required by conformance to `SomePeripheralDiscoveryMonitor`.
  ///
  /// - Parameters:
  ///   - mode: Scan mode (e.g. association or reconnection).
  ///   - discoveryHandler: Handler to call when a peripheral is discovered.
  ///   - cancelHandler: Handler to call when this monitor is canceled.
  required public init(
    mode: PeripheralScanMode,
    discoveryHandler: @escaping (Peripheral, DiscoveryContext?) -> Void,
    cancelHandler: @escaping () -> Void
  ) {
    self.mode = mode
    self.discoveryHandler = discoveryHandler
    self.cancelHandler = cancelHandler
  }

  /// Post the peripheral to the discovery handler.
  ///
  /// - Parameters:
  ///   - peripheral: The discovered peripheral.
  ///   - context: Context if any associated with the peripheral discovery.
  public func onPeripheralDiscovered(_ peripheral: Peripheral, context: DiscoveryContext? = nil) {
    discoveryHandler(peripheral, context)
  }

  /// Cancel this monitor call the cancel handler.
  public func cancel() {
    cancelHandler()
  }
}
