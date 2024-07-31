// Copyright 2024 Google LLC
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

#if os(iOS)

  fileprivate import Foundation
  internal import XCTest

  @testable private import AndroidAutoConnectedDeviceManager
  @testable private import AndroidAutoConnectedDeviceManagerMocks

  @available(iOS 17.0, *)
  class BeaconManagerTest: XCTestCase {
    private var uuidConfig: UUIDConfig!
    private var connectedCarManagerMock: ConnectedCarManagerMock!
    private var manager: BeaconManagerImpl<MockBeaconMonitor>!

    @MainActor override func setUp() {
      super.setUp()

      connectedCarManagerMock = ConnectedCarManagerMock()
      uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    }

    @MainActor func testStartMonitoring() async {
      await manager = BeaconManagerImpl(
        connectedCarManager: connectedCarManagerMock,
        uuidConfig: uuidConfig,
        monitorType: MockBeaconMonitor.self
      )

      XCTAssertTrue(manager.beaconMonitor!.startMonitoringCalled)
    }
  }

  private class MockBeaconMonitor: BeaconMonitor {
    fileprivate var startMonitoringCalled = false

    fileprivate var events: [String] = []

    fileprivate required init(_ name: String) {}

    fileprivate func add(_ condition: String, identifier: String) async {
      startMonitoringCalled = true
    }

    fileprivate func startMonitoringBeacon(uuid: UUID) async {
      await self.add("doesNothing", identifier: "mock")
    }
  }

#endif
