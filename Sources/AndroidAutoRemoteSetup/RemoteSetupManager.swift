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

public import AndroidAutoConnectedDeviceManager
private import AndroidAutoLogger
public import Foundation
public import RemoteSetup
public import UIKit

/// A manager for the remote setup feature which allows the user to setup their car from their
/// phone.
@MainActor public class RemoteSetupManager {
  private let managerCore: RemoteSetupManagerCore
  private let preferenceManager: RemoteSetupPreferenceManager

  public init(connectedCarManager: any ConnectedCarManager) {
    managerCore = RemoteSetupManagerCore(logger: Logger.self)
    preferenceManager = RemoteSetupPreferenceManager(connectedCarManager: connectedCarManager)
  }

  /// Launches the Google remote setup web application with an SFSafariViewController.
  ///
  /// This method starts the web application with user vehicle data provided through a
  /// [RemoteSetupVehicle] along with the device's locale to display a localized experience.
  public func startRemoteSetup(
    _ uiViewController: UIViewController,
    vehicle: RemoteSetupVehicle,
    configure: ((inout RemoteSetupManagerCore.SafariViewWrapper) -> Void)? = nil
  ) {
    managerCore.startRemoteSetup(uiViewController, vehicle: vehicle, configure: configure)
  }

  /// Finishes the Google remote setup process.
  ///
  /// Dismisses the web application if one is open.
  /// The redirectURL should be the complete URL sent to the companion app when the remote setup
  /// web app has successfully completed.
  public func finishRemoteSetup(redirectURL: URL) -> Bool {
    managerCore.finishRemoteSetup(redirectURL: redirectURL)
  }
}

// MARK: - Logger conformance to RemoteSetupLogger

extension Logger: RemoteSetupLogger {}
