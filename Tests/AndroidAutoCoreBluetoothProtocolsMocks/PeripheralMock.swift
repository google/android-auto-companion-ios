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

public import AndroidAutoCoreBluetoothProtocols
public import AndroidAutoConnectedDeviceTransport
public import CoreBluetooth
private import os

/// A mock of a `CBPeripheral` that allows its name and services to be set. It also contains
/// fields that allow a user to assert if its methods have been called and with what value.
@MainActor public class PeripheralMock: NSObject, BLEPeripheral {
  private var serviceObserver: ((any BLEPeripheral, [BLEService]) -> Void)? = nil

  public weak var delegate: BLEPeripheralDelegate?

  nonisolated public let identifier: UUID

  nonisolated public var identifierString: String { identifier.uuidString }

  nonisolated public let name: String?

  private let lockingState = OSAllocatedUnfairLock(initialState: CBPeripheralState.connected)

  public var state: CBPeripheralState {
    get {
      lockingState.withLock { $0 }
    }
    set {
      lockingState.withLock { state in
        state = newValue
      }
    }
  }

  public var services: [BLEService]?

  // Assertions for method calls.
  public var discoverServicesCalled = false

  public var serviceUUIDs: [CBUUID]?
  public var invalidatedServiceIDs: Set<String> = []

  public var discoverCharacteristicsCalled = false
  public var characteristicUUIDs: [CBUUID]?
  public var serviceToDiscoverFor: BLEService?

  public var readValueCalled = false
  public var notifyValueCalled = false
  public var notifyEnabled = false
  public var characteristicToNotifyFor: BLECharacteristic?
  public var characteristicToRead: BLECharacteristic?

  // The number of times the writeValue method was called.
  public var writeValueCalledCount = 0

  public var characteristicWrittenTo: [BLECharacteristic] = []
  public var writtenData: [Data] = []

  // 185 is the default write length for iOS 10.0 and above.
  public var maximumWriteValueLength = 185

  public init(identifier: UUID = UUID(), name: String?, services: [BLEService]?) {
    self.identifier = identifier
    self.name = name
    self.services = services
  }

  /// Creates a peripheral mock with `nil` services.
  public convenience init(identifier: UUID = UUID(), name: String?) {
    self.init(identifier: identifier, name: name, services: nil)
  }

  public func isServiceInvalidated(uuids: Set<String>) -> Bool {
    !invalidatedServiceIDs.isDisjoint(with: uuids)
  }

  /// Simulates an event where the peripheral's services has changed.
  public func triggerServiceModification(invalidatedServices: [BLEService]) {
    invalidatedServiceIDs.formUnion(invalidatedServices.map { $0.uuid.uuidString })
    serviceObserver?(self, invalidatedServices)
  }

  public func observeServiceModifications(
    using observation: @escaping (any BLEPeripheral, [BLEService]) -> Void
  ) {
    serviceObserver = observation
  }

  public func discoverServices(_ serviceUUIDs: [CBUUID]?) {
    discoverServicesCalled = true
    self.serviceUUIDs = serviceUUIDs
  }

  public func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: BLEService) {
    discoverCharacteristicsCalled = true
    self.characteristicUUIDs = characteristicUUIDs
    serviceToDiscoverFor = service
  }

  public func setNotifyValue(_ enabled: Bool, for characteristic: BLECharacteristic) {
    notifyEnabled = enabled
    notifyValueCalled = true
    characteristicToNotifyFor = characteristic
  }

  public func readValue(for characteristic: BLECharacteristic) {
    readValueCalled = true
    characteristicToRead = characteristic
  }

  public func writeValue(_ data: Data, for characteristic: BLECharacteristic) {
    writeValueCalledCount += 1

    writtenData.append(data)
    characteristicWrittenTo.append(characteristic)
  }

  /// Resets this mock back to its initialized state.
  ///
  /// Note: that this method does not reset the `name` and `services` of this peripheral.
  public func reset() {
    state = .connected
    delegate = nil

    discoverServicesCalled = false
    serviceUUIDs = nil

    discoverCharacteristicsCalled = false
    characteristicUUIDs = nil
    serviceToDiscoverFor = nil

    notifyValueCalled = false
    notifyEnabled = false
    characteristicToNotifyFor = nil

    writeValueCalledCount = 0
    characteristicWrittenTo = []
    writtenData = []

    maximumWriteValueLength = 185
  }
}
