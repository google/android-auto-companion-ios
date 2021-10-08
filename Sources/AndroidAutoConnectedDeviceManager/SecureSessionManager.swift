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

/// Generates and stores secure sessions.
///
/// Each secure session represents a key exchange between the car and phone.
protocol SecureSessionManager {
  /// The stored secure session for a given car or `nil` if none has been saved.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the secure session of `nil` if there was an error.
  func secureSession(for identifier: String) -> Data?

  /// Stores the given secure session for a car.
  ///
  /// - Parameters:
  ///   - secureSession: The session to save.
  ///   - identifier: The identifier for the car.
  /// - Returns: `true` if the operation was successful.
  func storeSecureSession(_ secureSession: Data, for identifier: String) -> Bool

  /// Clears any stored secure sessions for the given car.
  ///
  /// - Parameter identifier: the identifier of the car.
  func clearSecureSession(for identifier: String)
}
