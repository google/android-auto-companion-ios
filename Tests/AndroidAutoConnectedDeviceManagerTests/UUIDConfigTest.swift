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

import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `UUIDConfig`.
@available(watchOS 6.0, *)
class UUIDConfigTest: XCTestCase {
  private let expectedDefaultAssociationUUID =
    CBUUID(string: "5e2a68a4-27be-43f9-8d1e-4546976fabd7")
  private let expectedReconnectionV2UUID = CBUUID(string: "000000e0-0000-1000-8000-00805f9b34fb")

  // Both association and reconnection use the same default data UUID.
  private let expectedDefaultDataUUID = CBUUID(string: "00000020-0000-1000-8000-00805f9b34fb")

  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  // MARK: - Association UUID tests

  func testAssociationUUID_returnsDefaultValue() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    XCTAssertEqual(uuidConfig.associationUUID, expectedDefaultAssociationUUID)
  }

  func testAssociationUUID_returnsOverlaidValue() {
    let newUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let plistLoader = PListLoaderFake(
      overlayValues: [UUIDConfig.associationUUIDKey: newUUID.uuidString]
    )
    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.associationUUID, newUUID)
  }

  // MARK: - Association Data UUID tests

  func testAssociationDataUUID_returnsDefaultValue() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    XCTAssertEqual(uuidConfig.associationDataUUID, expectedDefaultDataUUID)
  }

  func testAssociationDataUUID_returnsOverlaidValue() {
    let newUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let plistLoader = PListLoaderFake(
      overlayValues: [UUIDConfig.associationDataUUIDKey: newUUID.uuidString]
    )
    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.associationDataUUID, newUUID)
  }

  // MARK: - Reconnection UUID tests

  func testReconnectionUUID_v1_returnsDeviceId() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v1), DeviceIdManager.deviceId)
  }

  func testReconnectionUUID_v2_returnsDefaultValue() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v2), expectedReconnectionV2UUID)
  }

  func testReconnectionUUID_returnsOverlaidValueforV2() {
    let newUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let plistLoader = PListLoaderFake(
      overlayValues: [UUIDConfig.reconnectionUUIDKey: newUUID.uuidString]
    )
    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v2), newUUID)
  }

  func testReconnectionUUID_overlaidValueDoesNotAffectV1() {
    let newUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let plistLoader = PListLoaderFake(
      overlayValues: [UUIDConfig.reconnectionUUIDKey: newUUID.uuidString]
    )
    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v1), DeviceIdManager.deviceId)
  }

  // MARK: - Reconnection Data UUID tests

  func testReconnectionDataUUID_returnsDefaultValue() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    XCTAssertEqual(uuidConfig.reconnectionDataUUID, expectedDefaultDataUUID)
  }

  func testReconnectionDataUUID_returnsOverlaidValue() {
    let newUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let plistLoader = PListLoaderFake(
      overlayValues: [UUIDConfig.reconnectionDataUUIDKey: newUUID.uuidString]
    )
    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.reconnectionDataUUID, newUUID)
  }

  // MARK: - Everything overlaid test

  func testAllOverlaidValues_returnsCorrectly() {
    let associationUUID = CBUUID(string: "541078e7-d6de-4ad2-b371-e443771287c7")
    let reconnectionUUID = CBUUID(string: "8a506dff-c869-43ff-a3b4-e06cb5575038")
    let dataUUID = CBUUID(string: "ef38de53-5a43-4f8f-8337-b99ce0ef755d")

    let plistLoader = PListLoaderFake(
      overlayValues: [
        UUIDConfig.associationUUIDKey: associationUUID.uuidString,
        UUIDConfig.reconnectionUUIDKey: reconnectionUUID.uuidString,
        UUIDConfig.reconnectionDataUUIDKey: dataUUID.uuidString,
      ]
    )

    let uuidConfig = UUIDConfig(plistLoader: plistLoader)

    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v1), DeviceIdManager.deviceId)
    XCTAssertEqual(uuidConfig.reconnectionUUID(for: .v2), reconnectionUUID)
    XCTAssertEqual(uuidConfig.associationUUID, associationUUID)
    XCTAssertEqual(uuidConfig.reconnectionDataUUID, dataUUID)
  }
}
