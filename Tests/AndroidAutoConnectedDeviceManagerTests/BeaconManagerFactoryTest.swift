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

  private import CoreLocation
  private import Foundation
  internal import XCTest

  @testable private import AndroidAutoConnectedDeviceManager
  @testable private import AndroidAutoConnectedDeviceManagerMocks

  class BeaconManagerFactoryTest: XCTestCase {
    private var uuidConfig: UUIDConfig!
    private var connectedCarManagerMock: ConnectedCarManagerMock!
    private var managerFactory: BeaconManagerFactory!

    override func setUp() async throws {
      try await super.setUp()

      await setUpOnMain()
    }

    @MainActor private func setUpOnMain() {
      connectedCarManagerMock = ConnectedCarManagerMock()
      uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
      managerFactory = BeaconManagerFactory()
    }

    @MainActor func testCreateBeaconManager_defaultToCLMonitor() async throws {
      let beaconManager = await managerFactory.makeBeaconManager(
        connectedCarManager: connectedCarManagerMock,
        uuidConfig: uuidConfig
      )

      if #available(iOS 17.0, *) {
        let manager = try XCTUnwrap(beaconManager, "Beacon manager should not be nil on iOS 17+.")
        XCTAssert(manager is BeaconManagerImpl<CLMonitor>)
      } else {
        XCTAssertNil(beaconManager)
      }
    }
  }

#endif
