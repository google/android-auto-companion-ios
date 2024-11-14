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

private import AndroidAutoCoreBluetoothProtocolsMocks
private import CoreBluetooth
internal import XCTest

@testable private import AndroidAutoConnectedDeviceManager

/// Unit tests for `ReconnectionHelperFactory`.
class ReconnectionHelperFactoryTest: XCTestCase {
  private static let identifier = UUID(uuidString: "f01caae0-1eb8-4753-8357-be83523828d5")!
  private let associatedCar = Car(
    id: ReconnectionHelperFactoryTest.identifier.uuidString, name: "name")

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false
  }

  override func tearDown() async throws {
    await tearDownOnMain()
  }

  @MainActor private func tearDownOnMain() {
    FakeCarAuthenticator.matchingData = nil
  }

  @MainActor func testMakeHelper_throwsIfNoServiceID() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    let peripheral = FakePeripheral(identifier: Self.identifier, name: "name")

    XCTAssertThrowsError(
      try ReconnectionHelperFactoryImpl.makeHelper(
        peripheral: peripheral,
        advertisement: [:],
        associatedCars: [associatedCar],
        uuidConfig: uuidConfig,
        authenticator: FakeCarAuthenticator.self
      )
    ) { error in
      XCTAssertEqual(error as? CommunicationManagerError, .serviceNotFound)
    }
  }

  @MainActor func testMakeHelper_returnsReconnectionHelperV1() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    let peripheral = FakePeripheral(identifier: Self.identifier, name: "name")

    let v1UUID = uuidConfig.reconnectionUUID(for: .v1)

    let reconnectionHelper = try? ReconnectionHelperFactoryImpl.makeHelper(
      peripheral: peripheral,
      advertisement: [CBAdvertisementDataServiceUUIDsKey: [v1UUID]],
      associatedCars: [associatedCar],
      uuidConfig: uuidConfig,
      authenticator: FakeCarAuthenticator.self
    )

    XCTAssert(reconnectionHelper is ReconnectionHelperV1)
  }

  @MainActor func testMakeHelper_noAdvertisement_notReadyForHandshake() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    let peripheral = FakePeripheral(identifier: Self.identifier, name: "name")

    let v2UUID = uuidConfig.reconnectionUUID(for: .v2)
    let matchingData = Data("matching".utf8)
    FakeCarAuthenticator.matchingData = matchingData

    let partialAdvertisement: Advertisement = [
      CBAdvertisementDataServiceUUIDsKey: [v2UUID],
      CBAdvertisementDataServiceDataKey: [:],
    ]

    let helper = try? ReconnectionHelperFactoryImpl.makeHelper(
      peripheral: peripheral,
      advertisement: partialAdvertisement,
      associatedCars: [associatedCar],
      uuidConfig: uuidConfig,
      authenticator: FakeCarAuthenticator.self
    )

    XCTAssertNotNil(helper)
    XCTAssert(helper is ReconnectionHelperV2)
    XCTAssertFalse(helper!.isReadyForHandshake)
  }

  @MainActor func testMakeHelper_throwsIfNotAssociated() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    let peripheral = FakePeripheral(identifier: Self.identifier, name: "name")

    let v2UUID = uuidConfig.reconnectionUUID(for: .v2)
    let dataUUID = uuidConfig.reconnectionDataUUID
    let dataContents = [dataUUID: Data()]

    let advertisement: Advertisement = [
      CBAdvertisementDataServiceUUIDsKey: [v2UUID],
      CBAdvertisementDataServiceDataKey: dataContents,
    ]

    XCTAssertThrowsError(
      try ReconnectionHelperFactoryImpl.makeHelper(
        peripheral: peripheral,
        advertisement: advertisement,
        associatedCars: [associatedCar],
        uuidConfig: uuidConfig,
        authenticator: FakeCarAuthenticator.self
      )
    ) { error in
      XCTAssertEqual(error as? CommunicationManagerError, .notAssociated)
    }
  }

  @MainActor func testMakeHelper_returnsReconnectionHelperV2() {
    let uuidConfig = UUIDConfig(plistLoader: PListLoaderFake())
    let peripheral = FakePeripheral(identifier: Self.identifier, name: "name")

    let matchingData = Data("matching".utf8)
    let v2UUID = uuidConfig.reconnectionUUID(for: .v2)
    let dataUUID = uuidConfig.reconnectionDataUUID
    let dataContents = [dataUUID: matchingData]

    FakeCarAuthenticator.matchingData = matchingData

    let advertisement: Advertisement = [
      CBAdvertisementDataServiceUUIDsKey: [v2UUID],
      CBAdvertisementDataServiceDataKey: dataContents,
    ]

    let helper = try? ReconnectionHelperFactoryImpl.makeHelper(
      peripheral: peripheral,
      advertisement: advertisement,
      associatedCars: [associatedCar],
      uuidConfig: uuidConfig,
      authenticator: FakeCarAuthenticator.self
    )

    XCTAssertNotNil(helper)
    XCTAssert(helper is ReconnectionHelperV2)
    XCTAssertTrue(helper?.isReadyForHandshake ?? false)
  }
}

private struct FakePeripheral: AutoPeripheral {
  let identifier: UUID
  let name: String?

  // `state` is unused but required for protocol conformance.
  let state: State = .disconnected

  enum State: Int, AutoPeripheralState {
    case disconnected
    case connecting
    case connected
    case disconnecting
  }
}

/// A fake `CarAuthenticator` that can be configured to return a first match.
private struct FakeCarAuthenticator: CarAuthenticator {
  /// The data to match when `first(among:matchingData:)` is called.
  @MainActor static var matchingData: Data? = nil

  init(carId: String) {}

  /// Returns the first entry in the `cars` set if the specified `matchingData` matches the
  /// field `matchingData`.
  @MainActor static func first(
    among cars: Set<Car>,
    matchingData advertisementData: Data
  ) -> CarAdvertisementMatch? {
    if self.matchingData == nil || self.matchingData != matchingData {
      return nil
    }

    if cars.isEmpty {
      return nil
    }

    let car = cars.first!
    return (car, Data())
  }

  static func randomSalt(size: Int) -> Data {
    // Not needed for this test.
    return Data()
  }

  func isMatch(challenge: Data, hmac: Data) -> Bool {
    // Not needed for this test.
    return false
  }
}
