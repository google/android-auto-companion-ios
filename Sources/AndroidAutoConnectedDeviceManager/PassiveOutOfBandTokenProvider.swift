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

/// `OutOfBandTokenProvider` that provides the most recent token that was posted to it.
class PassiveOutOfBandTokenProvider {
  private static let log = Logger(for: PassiveOutOfBandTokenProvider.self)

  private var token: OutOfBandToken?

  var hasToken: Bool { token != nil }

  /// Post the token as the latest for consumption upon request.
  ///
  /// - Parameter token: The token to cache upon request.
  func postToken(_ token: OutOfBandToken) {
    self.token = token
  }
}

// MARK: - OutOfBandTokenProvider Conformance

extension PassiveOutOfBandTokenProvider: OutOfBandTokenProvider {
  /// Request a token and call the completion handler when it's been resolved.
  ///
  /// This provider immediately calls the completion handler with its current token if any.
  ///
  /// - Parameter completion: The handler to call when the request is resolved.
  func requestToken(completion: (OutOfBandToken?) -> Void) {
    completion(token)
  }

  /// Removes any cached token.
  func reset() {
    token = nil
  }
}
