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

/// A fake `EscrowTokenManager` that stores tokens and handles in memory.
public class EscrowTokenManagerFake: EscrowTokenManager {
  public var tokens: [String: Data] = [:]
  public var handles: [String: Data] = [:]

  /// `true` if a call to `storeHandle(_:for:)` will succeed.
  public var storeHandleSucceeds = true

  /// `true` if the a call to `generateAndStoreToken(for:)` will succeed.
  public var generateTokenSucceeds = true

  public init() {}

  public func token(for identifier: String) -> Data? {
    return tokens[identifier]
  }

  public func handle(for identifier: String) -> Data? {
    return handles[identifier]
  }

  public func generateAndStoreToken(for identifier: String) -> Data? {
    guard generateTokenSucceeds else {
      return nil
    }

    let token = Data("token".utf8)
    tokens[identifier] = token

    return token
  }

  public func storeHandle(_ handle: Data, for identifier: String) -> Bool {
    guard storeHandleSucceeds else {
      return false
    }

    handles[identifier] = handle
    return true
  }

  public func clearToken(for identifier: String) {
    tokens[identifier] = nil
  }

  public func clearHandle(for identifier: String) {
    handles[identifier] = nil
  }

  /// Resets back to the default initialization state.
  public func reset() {
    handles = [:]
    tokens = [:]
    storeHandleSucceeds = true
    generateTokenSucceeds = true
  }
}
