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

import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager

// extend PeripheralMock to conform to SomePeripheral
extension PeripheralMock: SomePeripheral {
  // Empty: already satisfies the requirements
}

/// A mock central manager for testing ConnectionManager independent of CoreBluetooth.
public class CentralManagerMock: SomeCentralManager {
  // MARK: - Required properties
  public var state = CBManagerState.poweredOn
  public var isScanning = false

  // MARK: - Mock state tracking
  public var scanForPeripheralsCalled = false
  public var scanForPeripheralsExpectation: XCTestExpectation? = nil
  public var servicesToScanFor: [CBUUID]?

  public var stopScanCalled = false
  public var connectedPeripherals = Set<PeripheralMock>()

  public var cancelPeripheralConnectionCalled = false
  public var canceledPeripherals = [PeripheralMock]()

  public init() {}

  // MARK: - Required methods

  public func retrieveConnectedPeripherals(withServices serviceUUIDs: [CBUUID]) -> [Peripheral] {
    return Array(connectedPeripherals)
  }

  public func scanForPeripherals(withServices: [CBUUID]?, options: [String: Any]?) {
    scanForPeripheralsExpectation?.fulfill()
    scanForPeripheralsCalled = true
    servicesToScanFor = withServices
  }

  public func stopScan() {
    stopScanCalled = true
  }

  public func connect(_ peripheral: PeripheralMock, options: [String: Any]?) {
    connectedPeripherals.insert(peripheral)
  }

  public func cancelPeripheralConnection(_ peripheral: PeripheralMock) {
    cancelPeripheralConnectionCalled = true
    canceledPeripherals.append(peripheral)
  }
}

/// A `ConnectionManager` that allows for assertions on its lifecycle methods.
public class ConnectionManagerObservable: ConnectionManager<CentralManagerMock> {
  public var connectCalledCount = 0
  public var peripheralToConnect: Peripheral?

  public var onPeripheralConnectedCalled = false
  public var connectedPeripheral: Peripheral?

  public var onPeripheralDisconnectedCalled = false
  public var disconnectedPeripheral: Peripheral?

  public var onPeripheralConnectionFailedCalled = false
  public var failedConnectionPeripheral: Peripheral?
  public var failedConnectionError: NSError?

  public var registerServiceObserverCalled = false
  public var observedChannel: SecuredCarChannel?

  public var setupSecureChannelCalled = false
  public var associateCalled = false

  public override func connect(with peripheral: Peripheral) {
    connectCalledCount += 1
    peripheralToConnect = peripheral
  }

  public override func onPeripheralConnected(_ peripheral: Peripheral) {
    onPeripheralConnectedCalled = true
    connectedPeripheral = peripheral
  }

  public override func onPeripheralDisconnected(_ peripheral: Peripheral) {
    onPeripheralDisconnectedCalled = true
    disconnectedPeripheral = peripheral
  }

  public override func onPeripheralConnectionFailed(_ peripheral: Peripheral, error: NSError) {
    onPeripheralConnectionFailedCalled = true
    failedConnectionPeripheral = peripheral
    failedConnectionError = error
  }

  public override func registerServiceObserver(on channel: SecuredCarChannel) {
    registerServiceObserverCalled = true
    observedChannel = channel
  }

  public override func setupSecureChannel(with peripheral: Peripheral) {
    setupSecureChannelCalled = true
  }

  public override func associate(peripheral: Peripheral) {
    associateCalled = true
  }

  public override func peripheral(from channel: SecuredCarChannel) -> Peripheral? {
    guard let bleChannel = channel as? SecuredCarChannelPeripheral else { return nil }
    guard let blePeripheral = bleChannel.peripheral as? BLEPeripheral else { return nil }
    return peripheral(from: blePeripheral)
  }

  public override func peripheral(from blePeripheral: BLEPeripheral) -> Peripheral? {
    return blePeripheral as? PeripheralMock
  }
}

/// A mock connection manager association delegate for testing ConnectonManager
/// independent of CoreBluetooth.
public class ConnectionManagerAssociationDelegateMock: ConnectionManagerAssociationDelegate {
  // MARK: - Mock state tracking
  public var discoveredCars = Set<PeripheralMock>()
  public var didConnectCalledForPeripherals = Set<PeripheralMock>()
  public var advertisedName: String?

  public var didEncounterErrorCalled = false
  public var encounteredError: Error? = nil

  public init() {}

  // MARK: - ConnectionManagerAssociationDelegate

  public func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didDiscover anyCar: AnyPeripheral,
    advertisedName: String?
  ) {
    guard let car = anyCar as? PeripheralMock else {
      fatalError("car is not a PeripheralMock: \(type(of: anyCar))")
    }
    discoveredCars.insert(car)
    self.advertisedName = advertisedName
  }

  public func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didConnect anyPeripheral: AnyPeripheral
  ) {
    guard let peripheral = anyPeripheral as? PeripheralMock else {
      fatalError("car is not a PeripheralMock: \(type(of: anyPeripheral))")
    }
    didConnectCalledForPeripherals.insert(peripheral)
  }

  public func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didCompleteAssociationWithCar car: Car
  ) {
  }

  public func connectionManager(
    _ connectionManager: AnyConnectionManager,
    requiresDisplayOf pairingCode: String
  ) {
  }

  public func connectionManager(
    _ connectionManager: AnyConnectionManager,
    didEncounterError error: Error
  ) {
    didEncounterErrorCalled = true
    encounteredError = error
  }
}
