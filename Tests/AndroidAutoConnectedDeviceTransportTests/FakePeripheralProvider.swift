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

import AndroidAutoConnectedDeviceTransportFakes
import AndroidAutoLogger
import XCTest

@testable import AndroidAutoConnectedDeviceTransport

/// Fake peripheral provider for testing transport sessions.

class FakePeripheralProvider: TransportPeripheralProvider {
  typealias Peripheral = FakePeripheral

  static let log = Logger(for: FakePeripheralProvider.self)

  /// Monitor for peripheral discovery.
  public var discoveryMonitor: PeripheralDiscoveryMonitor<FakePeripheral>?

  /// State of the radio.
  var radioState = TransportRadioState.poweredOn

  /// Start scanning in the specified mode.
  func startPeripheralScan(mode: PeripheralScanMode) -> Bool {
    return true
  }

  /// Stop scanning for peripherals.
  func stopPeripheralScan() {}

  func postPeripheral(_ peripheral: FakePeripheral) {
    discoveryMonitor?.onPeripheralDiscovered(peripheral)
  }

  func requestConnection(_: Peripheral) {}

  func cancelConnection(_: Peripheral) {}
}
