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

/// Provides a security session.
public protocol SecurityProvider {
  /// Make a new security session.
  func makeSession() -> SecureSession

  /// Fetch a security session for the specified identifier and return it if it exists.
  ///
  /// - Parameter id: The peripheral identifier for which to fetch the security session.
  /// - Returns: The matching security session or `nil` if no match exists.
  func fetchSession(id: String) -> SecureSession?
}

/// Security session for establishing encryption.
public protocol SecureSession {
  /// Identifier of the peripheral associated with this session.
  var identifier: String { get set }

  /// Save the security session after having established a secure connection.
  func save()

  /// Establish a security session using the specified channel for the handshake.
  func establish(using channel: AnyTransportChannel)
}
