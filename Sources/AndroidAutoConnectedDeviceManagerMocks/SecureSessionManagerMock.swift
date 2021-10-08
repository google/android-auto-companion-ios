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

import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A mock `SecureSessionManager` that allows the secure session to be set and returned.
public class SecureSessionManagerMock: SecureSessionManager {
  public var secureSessions: [String: Data] = [:]

  /// The return value `storeSecureSession(_:for:)`. `true` indicates that that method succeeds.
  public var storeSecureSessionSucceeds = true

  public init() {}

  public func secureSession(for identifier: String) -> Data? {
    return secureSessions[identifier]
  }

  public func storeSecureSession(_ secureSession: Data, for identifier: String) -> Bool {
    guard storeSecureSessionSucceeds else {
      return false
    }

    secureSessions[identifier] = secureSession
    return true
  }

  public func clearSecureSession(for identifier: String) {
    secureSessions[identifier] = nil
  }

  /// Resets back to the default initialization state.
  public func reset() {
    secureSessions = [:]
    storeSecureSessionSucceeds = true
  }
}
