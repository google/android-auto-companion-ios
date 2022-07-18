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

import AndroidAutoLogger
import Foundation

/// Coalesces multiple out of band token providers into a single provider.
///
/// Forwards token events from its providers to its token handler and maintains the most recently
/// posted token.
@available(watchOS 6.0, *)
struct CoalescingOutOfBandTokenProvider<Provider: OutOfBandTokenProvider> {
  private static var log: Logger { Logger(for: CoalescingOutOfBandTokenProvider<Provider>.self) }

  /// The child providers.
  private(set) var providers: [Provider]

  /// Initializes this provider with child providers.
  ///
  /// - Parameter providers: The child providers to which to forward requests.
  init(_ providers: [Provider]) {
    self.providers = providers
  }

  /// Initializes this provider with child providers.
  ///
  /// - Parameter providers: The child providers to which to forward requests.
  init(_ providers: Provider...) {
    self.init(providers)
  }

  init(configure: (inout CoalescingOutOfBandTokenProvider) -> Void) {
    self.init([])
    configure(&self)
  }

  /// Register the specified provider as a source.
  ///
  /// - Parameter provider: The provider to register as a source.
  mutating func register(_ provider: Provider) {
    self.providers.append(provider)
  }
}

@available(watchOS 6.0, *)
extension CoalescingOutOfBandTokenProvider: OutOfBandTokenProvider {
  /// Prepare the registered providers for token requests.
  func prepareForRequests() {
    for provider in providers {
      provider.prepareForRequests()
    }
  }

  /// Close the registered providers for token requests.
  func closeForRequests() {
    for provider in providers {
      provider.closeForRequests()
    }
  }

  /// Request a token and call the completion handler when it's been resolved.
  ///
  /// The request is tied to the current child providers at the time the request was made since each
  /// such provider will be responsible for responding to the request.
  ///
  /// - Parameter completion: The handler to call once the request is complete.
  func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
    // Capture the current providers since these are the ones responsible for handling the request.
    let providers = self.providers

    // If there are no child providers, we can call completion immediately and bail.
    guard !providers.isEmpty else {
      completion(nil)
      return
    }

    // As soon as token is discovered, call completion and be done.
    var discoveredToken = false
    var pending = providers.count
    for provider in providers {
      provider.requestToken { token in
        guard !discoveredToken else { return }
        pending -= 1
        guard let token = token else {
          // No token, so check if this is the last pending provider.
          guard pending == 0 else { return }
          // Last pending provider, so we need to call the completion handler.
          completion(nil)
          return
        }
        completion(token)
        discoveredToken = true
      }
    }
  }

  /// Resets this provider.
  ///
  /// Removes any cached token and resolves any pending completion handlers.
  func reset() {
    providers.forEach { $0.reset() }
  }
}
