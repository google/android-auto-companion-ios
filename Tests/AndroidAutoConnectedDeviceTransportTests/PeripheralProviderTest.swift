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

/// Unit tests for default PeripheralProvider behaviors.
class PeripheralProviderTest: XCTestCase {
  private var peripheralProvider: TrialPeripheralProvider!
  private var mockDiscoveryHandler: MockPeripheralDiscoveryMonitorHandler!

  override func setUp() {
    super.setUp()

    peripheralProvider = TrialPeripheralProvider()
    mockDiscoveryHandler = MockPeripheralDiscoveryMonitorHandler()
  }

  override func tearDown() {
    peripheralProvider = nil
    mockDiscoveryHandler = nil

    super.tearDown()
  }

  func testScanForPeripheralsPostsDiscoveredPeripheral() {
    let monitor = peripheralProvider.scanForPeripherals(
      mode: .association, discoveryHandler: mockDiscoveryHandler.onDidDiscoverPeripheral)

    let peripheral = FakePeripheral()
    peripheralProvider.postPeripheral(peripheral)

    XCTAssertNotNil(mockDiscoveryHandler.discoveredPeripheral)
    XCTAssertEqual(peripheral, mockDiscoveryHandler.discoveredPeripheral)

    monitor.cancel()
  }

  func testScanForPeripheralsStartsPeripheralScan() {
    let monitor = peripheralProvider.scanForPeripherals(
      mode: .association, discoveryHandler: mockDiscoveryHandler.onDidDiscoverPeripheral)

    XCTAssertTrue(peripheralProvider.startPeripheralScanCalled)

    monitor.cancel()
  }

  func testCancelMonitorStopsPeripheralScan() {
    let monitor = peripheralProvider.scanForPeripherals(
      mode: .association, discoveryHandler: mockDiscoveryHandler.onDidDiscoverPeripheral)

    monitor.cancel()

    XCTAssertTrue(peripheralProvider.stopPeripheralScanCalled)
  }
}

private class TrialPeripheralProvider {
  var startPeripheralScanCalled = false
  var stopPeripheralScanCalled = false

  /// Required monitor for peripheral discovery.
  public var discoveryMonitor: PeripheralDiscoveryMonitor<FakePeripheral>? = nil

  /// State of the radio.
  var radioState = TransportRadioState.poweredOn

  /// Post a peripheral to the monitor for testing.
  fileprivate func postPeripheral(_ peripheral: FakePeripheral) {
    discoveryMonitor?.onPeripheralDiscovered(peripheral)
  }
}

/// Implement required PeripheralProvider implementations.
extension TrialPeripheralProvider: TransportPeripheralProvider {
  typealias Peripheral = FakePeripheral

  static let log = Logger(for: TrialPeripheralProvider.self)

  /// Start scanning in the specified mode.
  func startPeripheralScan(mode: PeripheralScanMode) -> Bool {
    startPeripheralScanCalled = true
    return isReady
  }

  /// Stop scanning for peripherals.
  func stopPeripheralScan() {
    stopPeripheralScanCalled = true
  }

  func requestConnection(_: Peripheral) {}

  func cancelConnection(_: Peripheral) {}
}

private class MockPeripheralDiscoveryMonitorHandler {
  var discoveredPeripheral: FakePeripheral? = nil

  func onDidDiscoverPeripheral(_ peripheral: FakePeripheral, context: Any?) {
    discoveredPeripheral = peripheral
  }
}
