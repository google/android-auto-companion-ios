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

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import CoreBluetooth
import Foundation

/// A wrapper around a `CBPeripheral` that will make it conform to `BLEPeripheral`.
class CBPeripheralWrapper: NSObject, BLEPeripheral {
  private var serviceObserver: ((BLEPeripheral, [BLEService]) -> Void)? = nil

  let peripheral: CBPeripheral

  private var invalidatedServiceIDs: Set<String> = []

  weak var delegate: BLEPeripheralDelegate?

  var identifier: UUID {
    return peripheral.identifier
  }

  var identifierString: String { identifier.uuidString }

  var name: String? {
    return peripheral.name
  }

  var state: CBPeripheralState {
    return peripheral.state
  }

  var services: [BLEService]? {
    return peripheral.services?.map { CBServiceWrapper(service: $0) }
  }

  var maximumWriteValueLength: Int {
    return peripheral.maximumWriteValueLength(for: .withoutResponse)
  }

  init(peripheral: CBPeripheral) {
    self.peripheral = peripheral
    super.init()
    peripheral.delegate = self
  }

  func isServiceInvalidated(uuids: Set<String>) -> Bool {
    !invalidatedServiceIDs.isDisjoint(with: uuids)
  }

  func observeServiceModifications(
    using observation: @escaping (BLEPeripheral, [BLEService]) -> Void
  ) {
    serviceObserver = observation
  }

  func discoverServices(_ serviceUUIDs: [CBUUID]?) {
    peripheral.discoverServices(serviceUUIDs)
  }

  func discoverCharacteristics(_ characteristicUUIDs: [CBUUID]?, for service: BLEService) {
    if let wrapper = service as? CBServiceWrapper {
      peripheral.discoverCharacteristics(characteristicUUIDs, for: wrapper.service)
    }
  }

  func setNotifyValue(_ enabled: Bool, for characteristic: BLECharacteristic) {
    if let cbCharacteristic = characteristic as? CBCharacteristicWrapper {
      peripheral.setNotifyValue(enabled, for: cbCharacteristic.characteristic)
    }
  }

  func readValue(for characteristic: BLECharacteristic) {
    if let cbCharacteristic = characteristic as? CBCharacteristicWrapper {
      peripheral.readValue(for: cbCharacteristic.characteristic)
    }
  }

  func writeValue(_ data: Data, for characteristic: BLECharacteristic) {
    if let cbCharacteristic = characteristic as? CBCharacteristicWrapper {
      peripheral.writeValue(data, for: cbCharacteristic.characteristic, type: .withoutResponse)
    }
  }
}

extension CBPeripheralWrapper: CBPeripheralDelegate {
  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    delegate?.peripheral(self, didDiscoverServices: error)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    delegate?.peripheral(
      self,
      didDiscoverCharacteristicsFor: CBServiceWrapper(service: service),
      error: error
    )
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    delegate?.peripheral(
      self,
      didUpdateValueFor: CBCharacteristicWrapper(characteristic: characteristic),
      error: error
    )
  }

  func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
    delegate?.peripheralIsReadyToWrite(self)
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didModifyServices invalidatedServices: [CBService]
  ) {
    let invalidatedServiceWrappers = invalidatedServices.map { CBServiceWrapper(service: $0) }
    invalidatedServiceIDs.formUnion(invalidatedServiceWrappers.map { $0.uuid.uuidString })
    serviceObserver?(self, invalidatedServiceWrappers)
  }
}
