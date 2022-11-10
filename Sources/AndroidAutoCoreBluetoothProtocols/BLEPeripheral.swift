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

import AndroidAutoConnectedDeviceTransport
import CoreBluetooth
import Foundation

/// A delegate to be notified of various connection updates on a `BLEPeripheral`.
public protocol BLEPeripheralDelegate: AnyObject {
  /// Invoked upon discovery of a peripheral's services.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral that the services were discovered for.
  ///   - error: The cause of the failure if an error occurred or `nil` if no error.
  func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?)

  /// Invoked when characteristics are discovered a peripheral.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral providing the characteristics.
  ///   - service: The service the characteristics belong to.
  ///   - error: The cause of the failure if an error occurred or `nil` if no error.
  func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  )

  /// Invoked when a specified characteristic has changed its value.
  ///
  /// For this method to be invoked, `setNotifyValue()` should be called with a value of `true`.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral providing the characteristic.
  ///   - characteristic: The characteristic that was updated.
  ///   - error: The cause of the failure if an error occurred or `nil` if no error.
  func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  )

  /// Invoked when this peripheral is ready for another message to be written.
  ///
  /// After calling `writeValue(_:for:)`, this method will be invoked when another write call
  /// is safe to be made.
  ///
  /// - Parameter peripheral: The peripheral that is ready to send messages.
  func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral)
}

/// A remote peripheral that supports BLE.
public protocol BLEPeripheral: AnyTransportPeripheral {
  /// A unique identifier for this peripheral.
  var identifier: UUID { get }

  /// The delegate that will be notified of any peripheral events. This delegate should be
  /// declared as `weak` if possible
  var delegate: BLEPeripheralDelegate? { get set }

  /// The name of the peripheral.
  var name: String? { get }

  /// The services of a peripheral that have been discovered. This value should only be populated
  /// after `discoverServices` has been called.
  var services: [BLEService]? { get }

  /// The connection state of this peripheral.
  var state: CBPeripheralState { get }

  /// The maximum length in bytes that can be written per message for this peripheral.
  var maximumWriteValueLength: Int { get }

  /// Determine whether the peripheral contains an invalidated service.
  ///
  /// - Parameter uuids: The UUIDs of the services to check.
  /// - Returns: `true` if any specified service is invalidated.
  func isServiceInvalidated(uuids: Set<String>) -> Bool

  /// Registers the `observation` to be called when this peripheral has modified its
  /// services.
  ///
  /// The observation is passed the peripheral itself and a list of services that have now been
  /// invalidated and are no longer on the peripheral.
  func observeServiceModifications(
    using observation: @escaping (BLEPeripheral, [BLEService]) -> Void
  )

  /// Discover the services of this peripheral.
  ///
  /// - Parameters:
  ///   - serviceUUIDs: An array of `CBUUID` that represent the UUIDs of the services to be
  ///         discovered.
  func discoverServices(_ serviceUUIDs: [CBUUID]?)

  /// Discover the given characteristics on the specified service.
  ///
  /// - Parameters:
  ///   - characteristicUUIDs: The `uuid`s of characteristics to be discovered.
  ///   - service: The service that should contain the characteristics.
  func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: BLEService)

  /// Sets any set `delegate` to be notified whenever the given characteristic has changed its
  /// value.
  ///
  /// - Parameters:
  ///   - enabled: Sets whether to call this instance's `delegate` when the given characteristic's
  ///       value has changed.
  ///   - characteristic: The characteristic to listen for updates on.
  func setNotifyValue(_ enabled: Bool, for characteristic: BLECharacteristic)

  /// Read the value for the specified characteristic.
  ///
  /// - Parameter characteristic: The characteristic to read.
  func readValue(for characteristic: BLECharacteristic)

  /// Writes the given data on the specified characteristic.
  ///
  /// Callers of this method should wait until the method `peripheralIsReadyToWrite(_:)` is invoked
  /// on the `PeripheralDelegate` before calling this method again.
  ///
  /// - Parameters:
  ///   - data: The data to write.
  ///   - characteristic: The characteristic to write on.
  func writeValue(_ data: Data, for characteristic: BLECharacteristic)
}

/// Default implementations.
extension BLEPeripheral {
  /// Returns a log-friendly name for the given `BLEPeripheral`.
  public var displayName: String { name ?? "no name" }

  /// Status for this peripheral based on the BLE peripheral state.
  public var status: PeripheralStatus {
    switch state {
    case .disconnected:
      return .disconnected
    case .connecting:
      return .connecting
    case .connected:
      return .connected
    case .disconnecting:
      return .disconnecting
    default:
      return .other(String(describing: state))
    }
  }
}
