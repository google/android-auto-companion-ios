// Copyright 2022 Google LLC
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

import AndroidAutoLogger
import Foundation

/// Type erasing out of band token provider.
@available(watchOS 6.0, *)
struct AnyOutOfBandTokenProvider: OutOfBandTokenProvider {
  /// Source provider whose type is erased.
  let source: OutOfBandTokenProvider

  /// Prepare the provider for a possible upcoming token request.
  func prepareForRequests() {
    source.prepareForRequests()
  }

  /// Close the provider for requests.
  func closeForRequests() {
    source.closeForRequests()
  }

  /// Request a token and call the completion handler when it's been resolved.
  ///
  /// - Parameter completion: The handler to call when the request is resolved.
  func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
    source.requestToken(completion: completion)
  }

  /// Resets this provider.
  func reset() {
    source.reset()
  }
}

// MARK: - CoalescingOutOfBandTokenProvider extension for AnyOutOfBandTokenProvider

@available(watchOS 6.0, *)
extension CoalescingOutOfBandTokenProvider where Provider == AnyOutOfBandTokenProvider {
  /// Register the provider by wrapping it within a type erasing token provider.
  ///
  /// - Parameter provider: The provider to wrap and register.
  mutating func register(wrapping provider: OutOfBandTokenProvider) {
    register(AnyOutOfBandTokenProvider(source: provider) as AnyOutOfBandTokenProvider)
  }
}
