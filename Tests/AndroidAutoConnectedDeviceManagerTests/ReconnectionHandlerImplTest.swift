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

import AndroidAutoConnectedDeviceManagerMocks
import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import AndroidAutoMessageStream
import AndroidAutoSecureChannel
import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `ReconnectionHandlerImpl`.

@MainActor class ReconnectionHandlerImplTest: XCTestCase {
  private let carId = "carId"
  private let car = PeripheralMock(name: "carName")
  private let savedSession = SecureBLEChannelMock.mockSavedSession

  private let secureSessionManagerMock = SecureSessionManagerMock()
  private let secureBLEChannelMock = SecureBLEChannelMock()

  private var messageStream: BLEMessageStream!
  private var reconnectionHandler: ReconnectionHandlerImpl!
  private var connectionHandle: ConnectionHandleFake!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    UserDefaultsStorage.shared.clearAll()

    car.reset()
    secureSessionManagerMock.reset()
    secureBLEChannelMock.reset()

    // The actual values of the read/write characteristics do not matter here. The UUIDs passed
    // to them will be feature-specific.
    let readCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad1"), value: nil)
    let writeCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad2"), value: nil)

    messageStream = BLEMessageStreamFactory.makeStream(
      version: .passthrough,
      peripheral: car,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCompression: true
    )

    connectionHandle = ConnectionHandleFake()
    reconnectionHandler = ReconnectionHandlerImpl(
      car: Car(id: carId, name: car.name),
      connectionHandle: connectionHandle,
      secureSession: savedSession,
      messageStream: messageStream,
      secureBLEChannel: secureBLEChannelMock,
      secureSessionManager: secureSessionManagerMock
    )
  }

  // MARK: - Establish encryption tests.

  func testEstablishEncryption_invokedSecureChannel() {
    XCTAssertNoThrow(try reconnectionHandler.establishEncryption())

    // A secure session should now be attempted to be established.
    XCTAssertTrue(secureBLEChannelMock.establishWithSavedSessionCalled)
    XCTAssertEqual(reconnectionHandler.state, .keyExchangeInProgress)
  }

  // MARK: - Encryption established tests.

  func testEncryptionEstablished_cannotSaveSession_notifiesDelegateOfError() {
    let delegate = ReconnectionHandlerDelegateMock()
    reconnectionHandler.delegate = delegate

    // Configure so that the saved session won't establish immediately.
    secureBLEChannelMock.savedSessionShouldInstantlyNotify = false

    XCTAssertNoThrow(try reconnectionHandler.establishEncryption())

    // Now simulate that the secure channel has been established, but the session cannot be
    // saved.
    secureSessionManagerMock.storeSecureSessionSucceeds = false
    reconnectionHandler.secureBLEChannel(secureBLEChannelMock, establishedUsing: messageStream)

    // Delegate should be notified.
    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.encounteredError, .cannotEstablishEncryption)

    XCTAssertEqual(reconnectionHandler.state, .error)
  }

  func testEncryptionEstablished_notifiesDelegate() {
    let delegate = ReconnectionHandlerDelegateMock()
    reconnectionHandler.delegate = delegate

    // Configure so that an establish call will notify the delegate (in this case, the
    // reconnectionHandler) immediately.
    secureBLEChannelMock.savedSessionShouldInstantlyNotify = true

    // Ensure that saves of a new secure session succeed.
    secureSessionManagerMock.storeSecureSessionSucceeds = true

    XCTAssertNoThrow(try reconnectionHandler.establishEncryption())

    // No need to call `secureBLEChannel(_:establishedUsing)` because setting
    // `savedSessionShouldInstantlyNotify` to true does it for us.
    XCTAssertEqual(reconnectionHandler.state, .authenticationEstablished)

    XCTAssertTrue(delegate.didEstablishSecureChannelCalled)
    XCTAssertNotNil(delegate.establishedChannel)

    let expectedCar = Car(id: carId, name: car.name)
    XCTAssertEqual(delegate.establishedChannel!.car, expectedCar)
  }

  func testEncryptionEstablished_encounteredError_notifiesDelegate() {
    let delegate = ReconnectionHandlerDelegateMock()
    reconnectionHandler.delegate = delegate

    secureBLEChannelMock.savedSessionShouldInstantlyNotify = false

    // Ensure that saves of a new secure session succeed.
    secureSessionManagerMock.storeSecureSessionSucceeds = true

    XCTAssertNoThrow(try reconnectionHandler.establishEncryption())

    XCTAssertEqual(reconnectionHandler.state, .keyExchangeInProgress)
    XCTAssertFalse(delegate.didEstablishSecureChannelCalled)

    reconnectionHandler.secureBLEChannel(secureBLEChannelMock, encounteredError: makeFakeError())

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.encounteredError, .cannotEstablishEncryption)
  }

  // MARK: - Helper functions.

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}

/// A mock `ReconnectionHandlerDelegate` that allow for verification of methods being called.
class ReconnectionHandlerDelegateMock: ReconnectionHandlerDelegate {
  var didEstablishSecureChannelCalled = false
  var establishedChannel: SecuredCarChannel?

  var didEncounterErrorCalled = false
  var encounteredError: ReconnectionHandlerError?

  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEstablishSecureChannel securedCarChannel: SecuredConnectedDeviceChannel
  ) {
    didEstablishSecureChannelCalled = true
    establishedChannel = securedCarChannel
  }

  func reconnectionHandler(
    _ reconnectionHandler: ReconnectionHandler,
    didEncounterError error: ReconnectionHandlerError
  ) {
    didEncounterErrorCalled = true
    encounteredError = error
  }
}
