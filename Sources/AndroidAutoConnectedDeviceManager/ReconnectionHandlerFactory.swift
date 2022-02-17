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

@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import Foundation

/// A creator of `ReconnectionHandler`.
protocol ReconnectionHandlerFactory {
  /// Creates a handler that can be used to set up secure communication with the given car.
  ///
  /// - Parameters:
  ///   - car: The car to communicate securely with.
  ///   - connectionHandle: A handle for managing connections to remote cars.
  ///   - secureSession: The data that represents a previous secure session with the car.
  ///   - messageStream: The stream that handles message sending.
  ///   - secureBLEChannel: The underlying stream that handles setup of secure communication.
  ///   - secureSessionManager: Manager for retrieving and storing secure sessions.
  func makeHandler(
    car: Car,
    connectionHandle: ConnectionHandle,
    secureSession: Data,
    messageStream: BLEMessageStream,
    secureBLEChannel: SecureBLEChannel,
    secureSessionManager: SecureSessionManager
  ) -> ReconnectionHandler
}
