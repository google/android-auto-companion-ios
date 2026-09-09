// Copyright 2026 Google LLC
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

import AndroidAutoConnectedDeviceManager
import AndroidAutoConnectedDeviceManagerMocks
import Foundation
import RemoteSetup
internal import Testing
import UIKit

@testable import AndroidAutoRemoteSetup

@MainActor
struct RemoteSetupManagerTest {
  private let connectedCarManager = ConnectedCarManagerMock()
  private let managerCore = MockRemoteSetupManagerCore()
  private let manager: RemoteSetupManager

  init() {
    manager = RemoteSetupManager(
      connectedCarManager: connectedCarManager,
      managerCore: managerCore
    )
  }

  @Test
  func startRemoteSetup_delegatesToCore() {
    let vehicle = buildVehicle()
    manager.startRemoteSetup(UIViewController(), vehicle: vehicle)
    #expect(managerCore.startedVehicle == vehicle)
  }

  @Test
  func finishRemoteSetup_delegatesToCore() {
    let url = URL(string: "https://example.com")!
    _ = manager.finishRemoteSetup(redirectURL: url)
    #expect(managerCore.finishedRedirectURL == url)
  }

  private func buildVehicle() -> RemoteSetupVehicle {
    return RemoteSetupVehicle(
      make: "make",
      model: "model",
      year: "1234",
      redirectURL: "https://example.com/done",
      brand: "brand",
      product: "product",
      device: "device",
      buildFingerprint: "fingerprint"
    )!
  }
}

@MainActor
class MockRemoteSetupManagerCore: RemoteSetupManagerCoreProtocol {
  var isWebAppLaunched: Bool = false
  var startedVehicle: RemoteSetupVehicle?
  var finishedRedirectURL: URL?

  func startRemoteSetup(
    _ uiViewController: UIViewController,
    vehicle: RemoteSetupVehicle,
    configure: ((inout RemoteSetupManagerCore.SafariViewWrapper) -> Void)? = nil
  ) {
    startedVehicle = vehicle
  }

  func finishRemoteSetup(redirectURL: URL) -> Bool {
    finishedRedirectURL = redirectURL
    return true
  }
}
