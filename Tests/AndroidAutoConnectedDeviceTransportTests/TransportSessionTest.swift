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

/// Unit tests for TransportSessionTest.
class TransportSessionTest: XCTestCase {
  private var peripheralProvider: FakePeripheralProvider!
  private var delegate: FakeTransportSessionDelegate!
  private var session: TransportSession<FakePeripheralProvider>!

  override func setUp() {
    super.setUp()

    peripheralProvider = FakePeripheralProvider()
    delegate = FakeTransportSessionDelegate()
    session = TransportSession(provider: peripheralProvider, delegate: delegate)
  }

  override func tearDown() {
    session = nil
    delegate = nil
    peripheralProvider = nil

    super.tearDown()
  }

  func testDiscoversAssociatedPeripherals() {
    session.scanForPeripherals(mode: .reconnection) { _, _ in }

    let firstPeripheral = FakePeripheral()
    peripheralProvider.postPeripheral(firstPeripheral)
    XCTAssertEqual(session.peripherals.count, 1)

    let secondPeripheral = FakePeripheral()
    peripheralProvider.postPeripheral(secondPeripheral)
    XCTAssertEqual(session.peripherals.count, 2)

    XCTAssertTrue(session.peripherals.contains(firstPeripheral))
    XCTAssertTrue(session.peripherals.contains(secondPeripheral))
    XCTAssertEqual(session.discoveredPeripherals.count, 2)
    XCTAssertTrue(session.discoveredPeripherals.contains(firstPeripheral))
    XCTAssertTrue(session.discoveredPeripherals.contains(secondPeripheral))

    XCTAssertEqual(delegate.discoveredAssociatedPeripherals.count, 2)
    XCTAssertTrue(
      delegate.discoveredAssociatedPeripherals.contains(where: {
        $0 === firstPeripheral
      }))
    XCTAssertTrue(
      delegate.discoveredAssociatedPeripherals.contains(where: {
        $0 === secondPeripheral
      }))

    XCTAssertEqual(delegate.discoveredUnassociatedPeripherals.count, 0)
  }

  func testDiscoversUnassociatedPeripherals() {
    session.scanForPeripherals(mode: .association) { _, _ in }

    let firstPeripheral = FakePeripheral()
    peripheralProvider.postPeripheral(firstPeripheral)
    XCTAssertEqual(session.peripherals.count, 1)

    let secondPeripheral = FakePeripheral()
    peripheralProvider.postPeripheral(secondPeripheral)
    XCTAssertEqual(session.peripherals.count, 2)

    XCTAssertTrue(session.peripherals.contains(firstPeripheral))
    XCTAssertTrue(session.peripherals.contains(secondPeripheral))
    XCTAssertEqual(session.discoveredPeripherals.count, 2)
    XCTAssertTrue(session.discoveredPeripherals.contains(firstPeripheral))
    XCTAssertTrue(session.discoveredPeripherals.contains(secondPeripheral))

    XCTAssertEqual(delegate.discoveredUnassociatedPeripherals.count, 2)
    XCTAssertTrue(
      delegate.discoveredUnassociatedPeripherals.contains(where: {
        $0 === firstPeripheral
      }))
    XCTAssertTrue(
      delegate.discoveredUnassociatedPeripherals.contains(where: {
        $0 === secondPeripheral
      }))

    XCTAssertEqual(delegate.discoveredAssociatedPeripherals.count, 0)
  }

  func testPropagatesStateChange() {
    session.scanForPeripherals(mode: .reconnection) { _, _ in }
    let peripheral = FakePeripheral()
    peripheralProvider.postPeripheral(peripheral)
    peripheral.status = .connecting
    XCTAssertEqual(delegate.connectingPeripherals.count, 1)
  }
}

private class FakeTransportSessionDelegate: TransportSessionDelegate {
  var discoveredAssociatedPeripherals: [AnyTransportPeripheral] = []
  var discoveredUnassociatedPeripherals: [AnyTransportPeripheral] = []
  var connectingPeripherals: [AnyTransportPeripheral] = []

  func session(
    _: AnyTransportSession, didDiscover peripheral: AnyTransportPeripheral, mode: PeripheralScanMode
  ) {
    switch mode {
    case .association:
      discoveredUnassociatedPeripherals.append(peripheral)
    case .reconnection:
      discoveredAssociatedPeripherals.append(peripheral)
    }
  }

  func session(
    _: AnyTransportSession, peripheral: AnyTransportPeripheral,
    didChangeStateTo state: PeripheralStatus
  ) {
    if case .connecting = state {
      connectingPeripherals.append(peripheral)
    }
  }
}
