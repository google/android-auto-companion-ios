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

@_implementationOnly import AndroidAutoSecureChannel
import Foundation

/// Additional internal requirements for a channel that can be used to send encrypted messages.
protocol SecuredConnectedDeviceChannel: SecuredCarChannel {
  /// Complete configuration of the channel with the specified feature provider.
  ///
  /// After the secure channel connection is established, use the feature provider to query for
  /// state that completes configuration of the channel.
  ///
  /// - Parameters:
  ///   - provider: The feature provider to query for the configuration.
  ///   - completion: Handler to call upon resolution of the configuration.
  func configure(
    using provider: ChannelFeatureProvider,
    completion: @escaping (SecuredConnectedDeviceChannel) -> Void
  )
}
