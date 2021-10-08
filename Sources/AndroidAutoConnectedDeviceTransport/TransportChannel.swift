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

/// Common conformance for a channel.
public protocol TransportChannel: AnyTransportChannel {
  associatedtype Peripheral: TransportPeripheral

  /// Peripheral for which the channel is providing communication.
  var peripheral: Peripheral { get }
}

/// Common channel conformance.
public protocol AnyTransportChannel: AnyObject {
  /// Peripheral for which the channel is providing communication.
  var peripheral: AnyTransportPeripheral { get }

  /// Receiver of read events.
  var onMessageRead: ((Result<Data, TransportChannelError>) -> Void)? { get set }

  /// Send a message.
  func writeMessage(
    _ message: Data,
    completion: ((TransportChannelError?) -> Void)?
  )
}

extension AnyTransportChannel where Self: TransportChannel {
  /// Get the peripheral as `AnyTransportPeripheral`.
  ///
  /// We shouldn't have to do this, but there has been a longstanding Swift bug:
  /// https://bugs.swift.org/browse/SR-522
  public var peripheral: AnyTransportPeripheral {
    return self.peripheral as AnyTransportPeripheral
  }
}

/// Channel error conditions.
public enum TransportChannelError: Swift.Error {
  case disconnected
  case readFailed
  case writeFailed
  case unknown
}
