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

/// AES-GCM Token passed through an out of band established channel.
protocol OutOfBandToken {
  /// Encrypts a plain message.
  ///
  /// - Parameter message: The plain message to encrypt.
  /// - Returns: The encrypted data followed by the 16 byte authenticaton tag.
  /// - Throws: An error encryption fails.
  func encrypt(_ message: Data) throws -> Data

  /// Decrypts an encrypted message.
  ///
  /// - Parameter message: The encrypted message followed by the 16 byte nonce.
  /// - Returns: The encrypted data followed by the 16 byte authentication tag.
  /// - Throws: An error encryption fails.
  func decrypt(_ message: Data) throws -> Data
}

enum OutOfBandTokenError: Error {
  case invalidDataSize(Int)
  case invalidNonce
  case unsupportedPlatform
}

/// Source of out of band tokens.
protocol OutOfBandTokenProvider: AnyObject {
  /// Request a token and call the completion handler when it's been resolved.
  ///
  /// The provider must call the completion handler exactly once per request indicating whether a
  /// token is available or not.
  ///
  /// - Parameter completion: The handler to call when the request is resolved.
  func requestToken(completion: @escaping (OutOfBandToken?) -> Void)

  /// Resets this provider.
  ///
  /// Removes any cached token and resolves any pending completion handlers.
  func reset()
}
