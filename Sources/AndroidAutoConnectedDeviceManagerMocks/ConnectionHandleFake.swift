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

import AndroidAutoMessageStream
import AndroidAutoSecureChannel
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A fake `ConnectionHandle` that will keep of if its methods have been called.
public final class ConnectionHandleFake: ConnectionHandle {
  public var disconnectCalled = false
  public var disconnectedStream: MessageStream?
  public var requestConfigurationCalled = false

  public init() {}

  public func disconnect(_ messageStream: MessageStream) {
    disconnectCalled = true
    disconnectedStream = messageStream
  }

  public func requestConfiguration(
    for channel: SecuredConnectedDeviceChannel,
    completion: @escaping () -> Void
  ) {
    completion()
    requestConfigurationCalled = true
  }
}
