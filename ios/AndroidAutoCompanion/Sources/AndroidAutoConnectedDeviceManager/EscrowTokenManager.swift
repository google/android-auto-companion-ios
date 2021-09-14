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

/// Generates and stores escrow tokens and handles that should be used for association.
protocol EscrowTokenManager {
  /// The stored escrow token or `nil` if `generateAndStoreToken` had not been called for
  /// the `identifier`, or there was an error.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the escrow token or `nil` if there was an error.
  func token(for identifier: String) -> Data?

  /// The stored handle or `nil` if `storeHandle` has not been called for the `identifier` or
  /// there was an error during the storage process.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the handle or `nil` if there was an error.
  func handle(for identifier: String) -> Data?

  /// Generates a random token to be used as an escrow that can be used to uniquely identify
  /// an association session.
  ///
  /// - Parameter identifier: The identifier of the car.
  /// - Returns: A `Data` object containing the escrow token or `nil` if there was an error.
  func generateAndStoreToken(for identifier: String) -> Data?

  /// Store the given `Data` object as the association handle that can be used to uniquely identify
  /// an association session.
  ///
  /// - Parameters:
  ///   - handle: The handle to store.
  ///   - identifier: The identifier of the car.
  /// - Returns: `true` if the storage of the handle was successful.
  func storeHandle(_ handle: Data, for identifier: String) -> Bool

  /// Clears any enrollment tokens that have been previously stored for the given identifier.
  ///
  /// - Parameter identifier: The identifier of the car.
  func clearToken(for identifier: String)

  /// Clears any enrollment handles that had previously been stored for an identifier.
  ///
  /// - Parameter identifier: The identifier of the car.
  func clearHandle(for identifier: String)
}
