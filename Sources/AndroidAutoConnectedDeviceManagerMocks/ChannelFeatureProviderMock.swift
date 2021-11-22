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

import AndroidAutoConnectedDeviceTransport
import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A mock of the `ChannelFeatureProvider`.
public class ChannelFeatureProviderMock: ChannelFeatureProvider {
  /// The user role to use for the result of the request.
  private let userRole: UserRole?

  /// Indicates whether `requestUserRole()` was called.
  public private(set) var requestUserRoleCalled = false

  convenience public init() {
    self.init(userRole: nil)
  }

  public init(userRole: UserRole?) {
    self.userRole = userRole
  }

  /// Request the user role (driver/passenger) with the specified channel.
  public func requestUserRole(
    with channel: SecuredCarChannel,
    completion: @escaping (UserRole?) -> Void
  ) {
    requestUserRoleCalled = true
    completion(userRole)
  }
}
