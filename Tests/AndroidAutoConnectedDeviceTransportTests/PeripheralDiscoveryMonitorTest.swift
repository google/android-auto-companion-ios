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
import XCTest

@testable import AndroidAutoConnectedDeviceTransport

/// Unit tests for PeripheralDiscoveryMonitor.

class PeripheralDiscoveryMonitorTest: XCTestCase {
  private var mockHandler: MockPeripheralDiscoveryMonitorHandler!
  private var monitor: PeripheralDiscoveryMonitor<FakePeripheral>!

  override func setUp() {
    super.setUp()

    mockHandler = MockPeripheralDiscoveryMonitorHandler()

    monitor = PeripheralDiscoveryMonitor(
      mode: .association,
      discoveryHandler: mockHandler.onDidDiscoverPeripheral,
      cancelHandler: mockHandler.onCanceled
    )
  }

  override func tearDown() {
    monitor = nil
    mockHandler = nil

    super.tearDown()
  }

  func testCancelCallsCancelHandler() {
    monitor.cancel()
    XCTAssertEqual(mockHandler.cancelCalledCount, 1)
  }

  func testPostCallsPeripheralDiscoveryHandler() {
    let peripheral = FakePeripheral()
    monitor.onPeripheralDiscovered(peripheral)
    XCTAssertEqual(peripheral, mockHandler.discoveredPeripheral)
  }
}

private class MockPeripheralDiscoveryMonitorHandler {
  var cancelCalledCount = 0
  var discoveredPeripheral: FakePeripheral? = nil

  func onDidDiscoverPeripheral(_ peripheral: FakePeripheral, context: Any?) {
    discoveredPeripheral = peripheral
  }

  func onCanceled() {
    cancelCalledCount += 1
  }
}
