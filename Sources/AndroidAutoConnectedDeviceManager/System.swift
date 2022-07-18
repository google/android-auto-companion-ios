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

/// Common device requirements.
protocol AnyDevice {
  var name: String { get }
  var model: String { get }
  var localizedModel: String { get }
  var systemName: String { get }
  var systemVersion: String { get }
  var batteryLevel: Float { get }
}

/// Common system requirements.
private protocol SomeSystem {
  /// System specific device type.
  associatedtype Device: AnyDevice

  /// Get the current device.
  static var currentDevice: Device { get }

  /// Determine whether the current device is unlocked.
  static var isCurrentDeviceUnlocked: Bool { get }

  /// Indicates whether this device can somehow be authenticated (e.g. passcode, biometrics, etc.).
  static var canAuthenticateDevice: Bool { get }
}

#if os(iOS)

  import UIKit
  import LocalAuthentication

  extension UIDevice: AnyDevice {}

  /// Provides a common API to access system specific members.
  enum System: SomeSystem {
    /// Get the current device.
    static var currentDevice: UIDevice { UIDevice.current }

    /// Determine whether the current device is unlocked.
    static var isCurrentDeviceUnlocked: Bool { UIApplication.shared.isProtectedDataAvailable }

    /// Indicates whether this device can somehow be authenticated (e.g. passcode or biometrics).
    static var canAuthenticateDevice: Bool {
      LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
  }

#elseif os(watchOS)

  import WatchKit

  @available(watchOS 6.0, *)
  extension WKInterfaceDevice: AnyDevice {}

  /// Provides a common API to access system specific members.
  @available(watchOS 6.0, *)
  enum System: SomeSystem {
    /// Get the current device.
    static var currentDevice: WKInterfaceDevice { WKInterfaceDevice.current() }

    /// Determine whether the current device is unlocked.
    ///
    /// The watch must be unlocked to run this app, so the value must always be `true`.
    static var isCurrentDeviceUnlocked: Bool { true }

    /// Indicates whether this device can somehow be authenticated (e.g. passcode or biometrics).
    ///
    /// WatchOS currently has no API for device level authentication.
    static var canAuthenticateDevice: Bool { false }
  }

#endif
