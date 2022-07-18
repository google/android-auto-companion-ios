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
import AndroidAutoSecureChannel
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// An implementation of `CommunicationManagerDelegate` that allows for verification of its methods
/// being called.

class CommunicationManagerDelegateFake: CommunicationManagerDelegate {
  var establishingSecureChannelCalled = false
  var establishingCar: Car?
  var establishingPeripheral: BLEPeripheral?

  var didEstablishSecureChannelCalled = false
  var securedCarChannel: SecuredCarChannel?

  var errorExpectation: XCTestExpectation?
  var didEncounterErrorCalled = false
  var error: CommunicationManagerError?
  var peripheralWithError: BLEPeripheral?

  func communicationManager(
    _ communicationManager: CommunicationManager,
    establishingEncryptionWith car: Car,
    peripheral: BLEPeripheral
  ) {
    establishingSecureChannelCalled = true
    establishingCar = car
    establishingPeripheral = peripheral
  }

  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  ) {
    didEstablishSecureChannelCalled = true
    self.securedCarChannel = securedCarChannel
  }

  func communicationManager(
    _ communicationManager: CommunicationManager,
    didEncounterError error: CommunicationManagerError,
    whenReconnecting peripheral: BLEPeripheral
  ) {
    self.error = error

    didEncounterErrorCalled = true
    peripheralWithError = peripheral
    errorExpectation?.fulfill()
  }
}
