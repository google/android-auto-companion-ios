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

public import CoreBluetooth

// MARK: - TransportPeripheralState

/// Status of a peripheral.
public protocol TransportPeripheralState: Equatable {
  /// The peripheral is not connected.
  static var disconnected: Self { get }

  /// Connection to the peripheral has commenced.
  static var connecting: Self { get }

  /// The peripheral is connected (possibly without encryption).
  static var connected: Self { get }

  /// The connection to the peripheral is being terminated.
  static var disconnecting: Self { get }
}

// MARK: - TransportPeripheral

/// Homogeneous protocol for a peripheral using a specific communication transport.
public protocol TransportPeripheral: AnyObject, Hashable, Identifiable {
  associatedtype State: TransportPeripheralState

  /// Unique identifier for the peripheral.
  var identifierString: String { get }

  /// Name to display for the peripheral.
  var displayName: String { get }

  /// Peripheral name that can be logged.
  var logName: String { get }

  /// Indicates whether the peripheral is connected.
  var isConnected: Bool { get }

  /// Current status for this peripheral.
  var state: State { get }
}

// MARK: - TransportPeripheral Extensions

/// Default `TransportPeripheral` implementations.
extension TransportPeripheral {
  /// By default, the logName is just the displayName.
  public var logName: String { displayName }

  public var isConnected: Bool {
    state == .connected
  }
}

/// Default `Hashable` conformance implementation for a peripheral.
extension TransportPeripheral {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.id == rhs.id
  }
}

extension TransportPeripheral where ID: CustomStringConvertible {
  /// By default, the value is just `id.description`.
  public var identifierString: String { id.description }
}

extension TransportPeripheral where ID: Hashable {
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

// MARK: - TransportPeripheralState Conformance

extension CBPeripheralState: TransportPeripheralState {}
