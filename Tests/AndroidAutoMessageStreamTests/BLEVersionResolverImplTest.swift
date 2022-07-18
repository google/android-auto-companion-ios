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
import AndroidAutoCompanionProtos

@testable import AndroidAutoMessageStream

private typealias VersionExchange = Com_Google_Companionprotos_VersionExchange

/// Unit tests for `BLEVersionResolverImpl`.
class BLEVersionResolverImplTest: XCTestCase {
  private var bleVersionResolver: BLEVersionResolverImpl!

  // The read and write characteristics. The actual UUIDs of these characteristics do not matter.
  private let readCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad1"), value: nil)

  private let writeCharacteristic = CharacteristicMock(uuid: CBUUID(string: "bad2"), value: nil)

  private let peripheralMock = PeripheralMock(name: "mock", services: nil)
  private let delegateMock = BLEVersionResolverDelegateMock()

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    readCharacteristic.value = nil
    writeCharacteristic.value = nil

    delegateMock.reset()
    peripheralMock.reset()

    bleVersionResolver = BLEVersionResolverImpl()
    bleVersionResolver.delegate = delegateMock
  }

  // MARK: - Peripheral set up tests.

  func testResolveVersion_correctlySetsNotifyOnReadCharacteristic() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    XCTAssertTrue(peripheralMock.notifyEnabled)
    XCTAssertTrue(peripheralMock.notifyValueCalled)
    XCTAssert(peripheralMock.characteristicToNotifyFor === readCharacteristic)
  }

  func testResolveVersion_correctlySetsPeripheralDelegate() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    XCTAssert(peripheralMock.delegate === bleVersionResolver)
  }

  // MARK: - Created proto validation test

  func testVersionResolver_createsCorrectVersionProto() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // Assert proto has been written to the peripheral.
    XCTAssertEqual(peripheralMock.writtenData.count, 1)

    // Now assert the version information.
    let versionProto = try! VersionExchange(
      serializedData: peripheralMock.writtenData[0])

    XCTAssertEqual(versionProto.maxSupportedMessagingVersion, 3)
    XCTAssertEqual(versionProto.minSupportedMessagingVersion, 2)
    XCTAssertEqual(versionProto.maxSupportedSecurityVersion, 4)
    XCTAssertEqual(versionProto.minSupportedSecurityVersion, 1)
  }

  // MARK: - Valid version resolution tests.

  func testResolveVersion_correctlyResolvesVersionWithSameMaxMin() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // A version exchange proto whose messaging and security versions have the same max and min.
    let versionExchangeProto = makeVersionExchangeProto(messagingVersion: 2, securityVersion: 1)
    notify(from: peripheralMock, withValue: versionExchangeProto)

    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(false))
    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v1)
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesStreamVersionToTwo() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 3,
      minSupportedMessagingVersion: 2,
      maxSupportedSecurityVersion: 1,
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(true))
    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v1)
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesSecurityVersionToTwo() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 2,
      minSupportedMessagingVersion: 2,
      maxSupportedSecurityVersion: 2,
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v2)
    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(false))
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesSecurityVersionToThree() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 2,
      minSupportedMessagingVersion: 2,
      maxSupportedSecurityVersion: 3,
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v3)
    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(false))
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesWithCapabilitiesExchange() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: true
    )

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 2,
      minSupportedMessagingVersion: 2,
      maxSupportedSecurityVersion: 3,  // Only version 3 exchanges capabilities.
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    // Any response from the peripheral for capabilities response will do as payload is ignored.
    notify(from: peripheralMock, withValue: Data())

    // Version + capabilities responses.
    XCTAssertEqual(peripheralMock.writtenData.count, 2)

    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v3)
    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(false))
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesSecurityVersionToFour() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: true
    )

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 2,
      minSupportedMessagingVersion: 2,
      maxSupportedSecurityVersion: 4,
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v4)
    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(false))
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  func testResolveVersion_correctlyResolvesIfMinimumVersionMatches() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    let maxVersion: Int32 = 10
    let securityVersion: Int32 = 1

    // A version exchange proto that has a range, but its minimum version is the correct one.
    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: maxVersion,
      minSupportedMessagingVersion: securityVersion,
      maxSupportedSecurityVersion: maxVersion,
      minSupportedSecurityVersion: securityVersion
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    // Should now take the highest available version
    XCTAssertEqual(delegateMock.resolvedStreamVersion, .v2(true))
    XCTAssertEqual(delegateMock.resolvedSecurityVersion, .v4)
    XCTAssert(delegateMock.resolvedPeripheral === peripheralMock)

    XCTAssertNil(delegateMock.encounteredError)
  }

  // MARK: - Invalid version resolution test.

  func testResolveVersion_MessageStreamVersionNotSupported() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // A version exchange proto that does not support message stream version 1 or 2.
    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 20,
      minSupportedMessagingVersion: 10,
      maxSupportedSecurityVersion: 4,
      minSupportedSecurityVersion: 1
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    // Delegate should be notified of error.
    XCTAssertEqual(delegateMock.encounteredError, .versionNotSupported)
    XCTAssertNil(delegateMock.resolvedStreamVersion)
    XCTAssertNil(delegateMock.resolvedSecurityVersion)
    XCTAssertNil(delegateMock.resolvedPeripheral)
  }

  func testResolveVersion_SecurityVersionNotSupported() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // A version exchange proto that does not support security version between 1 and 4.
    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: 2,
      minSupportedMessagingVersion: 1,
      maxSupportedSecurityVersion: 20,
      minSupportedSecurityVersion: 10
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    // Delegate should be notified of error.
    XCTAssertEqual(delegateMock.encounteredError, .versionNotSupported)
    XCTAssertNil(delegateMock.resolvedStreamVersion)
    XCTAssertNil(delegateMock.resolvedSecurityVersion)
    XCTAssertNil(delegateMock.resolvedPeripheral)
  }

  func testResolveVersion_invalidIfNoSupportedVersionPresent() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // A version exchange proto that does not support version 1 or 2.
    let maxVersion: Int32 = 20
    let minVersion: Int32 = 10

    let versionExchangeProto = makeVersionExchangeProto(
      maxSupportedMessagingVersion: maxVersion,
      minSupportedMessagingVersion: minVersion,
      maxSupportedSecurityVersion: maxVersion,
      minSupportedSecurityVersion: minVersion
    )

    notify(from: peripheralMock, withValue: versionExchangeProto)

    // Delegate should be notified of error.
    XCTAssertEqual(delegateMock.encounteredError, .versionNotSupported)
    XCTAssertNil(delegateMock.resolvedStreamVersion)
    XCTAssertNil(delegateMock.resolvedSecurityVersion)
    XCTAssertNil(delegateMock.resolvedPeripheral)
  }

  // MARK: - Peripheral error tests.

  func testUpdateError_correctlyNotifiesDelegate() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // Error when updating a value on a characteristic.
    bleVersionResolver.peripheral(
      peripheralMock,
      didUpdateValueFor: readCharacteristic,
      error: makeFakeError()
    )

    XCTAssertEqual(delegateMock.encounteredError, .failedToRead)
    XCTAssertNil(delegateMock.resolvedStreamVersion)
    XCTAssertNil(delegateMock.resolvedSecurityVersion)
    XCTAssertNil(delegateMock.resolvedPeripheral)
  }

  func testEmptyResponse_correctlyNotifiesDelegate() {
    bleVersionResolver.resolveVersion(
      with: peripheralMock,
      readCharacteristic: readCharacteristic,
      writeCharacteristic: writeCharacteristic,
      allowsCapabilitiesExchange: false
    )

    // Empty response for the read characteristic.
    readCharacteristic.value = nil
    bleVersionResolver.peripheral(
      peripheralMock,
      didUpdateValueFor: readCharacteristic,
      error: nil
    )

    XCTAssertEqual(delegateMock.encounteredError, .emptyResponse)
    XCTAssertNil(delegateMock.resolvedStreamVersion)
    XCTAssertNil(delegateMock.resolvedSecurityVersion)
    XCTAssertNil(delegateMock.resolvedPeripheral)
  }

  // MARK: - Convenience functions.

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }

  private func notify(from peripheral: BLEPeripheral, withValue value: Data) {
    readCharacteristic.value = value
    bleVersionResolver.peripheral(peripheral, didUpdateValueFor: readCharacteristic, error: nil)
  }

  /// Makes a version exchange proto whose max and minimum versions are the same as the ones given.
  private func makeVersionExchangeProto(messagingVersion: Int32, securityVersion: Int32) -> Data {
    return makeVersionExchangeProto(
      maxSupportedMessagingVersion: messagingVersion,
      minSupportedMessagingVersion: messagingVersion,
      maxSupportedSecurityVersion: securityVersion,
      minSupportedSecurityVersion: securityVersion
    )
  }

  private func makeVersionExchangeProto(
    maxSupportedMessagingVersion: Int32,
    minSupportedMessagingVersion: Int32,
    maxSupportedSecurityVersion: Int32,
    minSupportedSecurityVersion: Int32
  ) -> Data {
    var versionExchange = VersionExchange()

    versionExchange.maxSupportedMessagingVersion = maxSupportedMessagingVersion
    versionExchange.minSupportedMessagingVersion = minSupportedMessagingVersion
    versionExchange.maxSupportedSecurityVersion = maxSupportedSecurityVersion
    versionExchange.minSupportedSecurityVersion = minSupportedSecurityVersion

    return try! versionExchange.serializedData()
  }
}

// MARK: - BLEVersionResolverDelegateMock

private class BLEVersionResolverDelegateMock: BLEVersionResolverDelegate {
  var resolvedStreamVersion: MessageStreamVersion?
  var resolvedSecurityVersion: MessageSecurityVersion?
  var resolvedPeripheral: BLEPeripheral?

  var encounteredError: BLEVersionResolverError?

  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didResolveStreamVersionTo streamVersion: MessageStreamVersion,
    securityVersionTo securityVersion: MessageSecurityVersion,
    for peripheral: BLEPeripheral
  ) {
    resolvedStreamVersion = streamVersion
    resolvedSecurityVersion = securityVersion
    resolvedPeripheral = peripheral
  }

  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didEncounterError error: BLEVersionResolverError,
    for peripheral: BLEPeripheral
  ) {
    encounteredError = error
  }

  func reset() {
    resolvedStreamVersion = nil
    resolvedSecurityVersion = nil
    resolvedPeripheral = nil
    encounteredError = nil
  }
}
