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

import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// `CarAuthenticatorImpl` unit tests.
class CarAuthenticatorImplTest: XCTestCase {
  // MARK: - Tests

  /// Test that the authenticator generates 256 bit keys.
  func testGenerates256BitKeys() {
    let authenticator = CarAuthenticatorImpl()

    XCTAssertEqual(authenticator.key.count, 32)
  }

  /// Test that independent authenticators generate different keys.
  func testGeneratesUniqueKeys() {
    let authenticator1 = CarAuthenticatorImpl()
    let authenticator2 = CarAuthenticatorImpl()

    XCTAssertNotEqual(authenticator1.key, authenticator2.key)
  }

  /// Test that key assignments with the wrong number of bits throw an error.
  func testBadKeySizeThrows() {
    XCTAssertThrowsError(try CarAuthenticatorImpl(key: [2, 3, 5, 7]))
  }

  /// Test that key -> data -> key regenerates an equivalent authenticator.
  func testRegenerateKeyFromData() {
    let authenticator = CarAuthenticatorImpl()
    let copy = try! CarAuthenticatorImpl(keyData: authenticator.keyData)

    let data = randomData(count: 16)
    let hmac1 = authenticator.computeHMAC(data: data)
    let hmac2 = copy.computeHMAC(data: data)

    XCTAssertEqual(authenticator.key, copy.key)
    XCTAssertEqual(hmac1, hmac2)
  }

  /// Pass data of varying length and test that we always get a 256 bit mac.
  func testGenerates256BitHMAC() {
    let authenticator = CarAuthenticatorImpl()

    for _ in 0..<100 {
      let size = Int.random(in: 1...5000)
      let data = randomData(count: size)
      let hmac1 = authenticator.computeHMAC(data: data)
      XCTAssertEqual(hmac1.count, 32)
    }
  }

  /// Test that different input data results in different macs.
  /// The HMACs should be random enough that feasibly this should always pass.
  func testUniqueDataGeneratesUniqueHMAC() {
    let authenticator = CarAuthenticatorImpl()

    let data1 = Data("test1".utf8)
    let data2 = Data("test2".utf8)

    let hmac1 = authenticator.computeHMAC(data: data1)
    let hmac2 = authenticator.computeHMAC(data: data2)

    XCTAssertEqual(hmac1.count, 32)
    XCTAssertEqual(hmac2.count, 32)
    XCTAssertNotEqual(hmac1, hmac2)
  }

  /// Test that the same authenticator generates the same input given the same data.
  func testGeneratesSameHMACForSameInput() {
    let authenticator = CarAuthenticatorImpl()

    let data = Data("test".utf8)

    let hmac1 = authenticator.computeHMAC(data: data)
    let hmac2 = authenticator.computeHMAC(data: data)

    XCTAssertEqual(hmac1.count, 32)
    XCTAssertEqual(hmac2.count, 32)
    XCTAssertEqual(hmac1, hmac2)
  }

  func testRandomSaltsNotEqual() {
    let salt1 = CarAuthenticatorImpl.randomSalt(size: 12)
    let salt2 = CarAuthenticatorImpl.randomSalt(size: 12)
    XCTAssertNotEqual(salt1, salt2)
  }

  func testRandomSaltSizes() {
    for _ in 1...100 {
      let size = Int.random(in: 1...5000)
      let salt1 = CarAuthenticatorImpl.randomSalt(size: size)
      XCTAssertEqual(salt1.count, size)
    }
  }

  func testSaveRestoreRemoveKey() {
    let id = UUID().uuidString
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: id))
    let match = try? CarAuthenticatorImpl(carId: id)
    XCTAssertNotNil(match)
    XCTAssertNoThrow(try CarAuthenticatorImpl.removeKey(forIdentifier: id))
    let removed = try? CarAuthenticatorImpl(carId: id)
    XCTAssertNil(removed)
  }

  func testMismatchLookupThrowsUnknownCar() {
    XCTAssertThrowsError(try CarAuthenticatorImpl(carId: "bad")) { (error) in
      guard case let CarAuthenticatorImpl.KeyError.unknownCar(carId) = error else {
        XCTFail("Expected unknownCar, but got a different error: \(error).")
        return
      }
      XCTAssertEqual(carId, "bad")
    }
  }

  func testAdvertisementPartionThrowsForInvalidLength() {
    // The valid advertisement length is 11.
    let invalidAd = randomData(count: 8)

    XCTAssertThrowsError(try CarAuthenticatorImpl.Advertisement.partition(advertisement: invalidAd))
  }

  func testAdvertisementPartionDoesntThrowForValidLength() {
    // The valid advertisement length is 11.
    let validAd = randomData(count: 11)

    XCTAssertNoThrow(try CarAuthenticatorImpl.Advertisement.partition(advertisement: validAd))
  }

  func testAdvertisementPartition() {
    // The valid advertisement length is 11.
    let advertisement = randomData(count: 11)

    do {
      let partition = try CarAuthenticatorImpl.Advertisement.partition(advertisement: advertisement)
      XCTAssertEqual(partition.truncatedHMAC.count, 3)

      // The padded salt is the original 8 bytes from the advertisement padded with 8 more zeros.
      XCTAssertEqual(partition.paddedSalt.count, 16)

      // Regenerate the advertisement from the partition.
      let regeneratedAd: Data = partition.truncatedHMAC + partition.paddedSalt[0..<8]
      XCTAssertEqual(advertisement, regeneratedAd)
    } catch {
      XCTFail("Partition of valid advertisement failed with error: \(error)")
    }
  }

  func testLengthOfTruncatedHMAC() {
    let hmac = randomData(count: 32)
    let truncatedHMAC = CarAuthenticatorImpl.Advertisement.truncateHMAC(hmac: hmac)

    XCTAssertEqual(truncatedHMAC.count, 3)
  }

  func testFindingMatchingCarForAdvertisementData() {
    // Create several cars to associate.
    let aCar = Car(id: "a", name: "hello")
    let testCar = Car(id: "t", name: "test")  // The car to match.
    let cCar = Car(id: "c", name: "world")
    let dCar = Car(id: "d", name: "d")
    let cars: Set<Car> = [aCar, testCar, cCar, dCar]

    // Associate several cars.
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: aCar.id))
    let authenticator = CarAuthenticatorImpl()
    XCTAssertNoThrow(try authenticator.saveKey(forIdentifier: testCar.id))
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: cCar.id))
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: dCar.id))

    // Cleanup
    defer {
      try? CarAuthenticatorImpl.removeKey(forIdentifier: aCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: testCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: cCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: dCar.id)
    }

    // Generate the advertisement that matches our test car.
    // 1) Generate a random eight byte salt and zero-pad it to sixteen bytes.
    // 2) Compute the HMAC for the padded salt and truncate it to three bytes.
    // 3) The advertisement is the truncated HMAC followed by the salt.
    let salt = CarAuthenticatorImpl.randomSalt(size: 8)
    let paddedSalt = Array(salt) + Array(repeating: 0, count: 8)
    let paddedSaltData = Data(bytes: paddedSalt, count: paddedSalt.count)
    let hmac = authenticator.computeHMAC(data: paddedSaltData)
    let advertisement = Data(hmac[0..<3] + salt)
    XCTAssertEqual(advertisement.count, 11)

    guard let match = CarAuthenticatorImpl.first(among: cars, matchingData: advertisement)
    else {
      XCTFail("Failed to find matching car.")
      return
    }

    XCTAssertEqual(testCar, match.car)
  }

  func testNoMatchingCarForAdvertisementData() {
    // Create several cars to associate.
    let aCar = Car(id: "a", name: "hello")
    let bCar = Car(id: "b", name: "something")
    let cCar = Car(id: "c", name: "world")
    let dCar = Car(id: "d", name: "d")
    let cars: Set<Car> = [aCar, bCar, cCar, dCar]

    // Associate several cars.
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: aCar.id))
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: bCar.id))
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: cCar.id))
    XCTAssertNoThrow(try CarAuthenticatorImpl().saveKey(forIdentifier: dCar.id))

    // Cleanup
    defer {
      try? CarAuthenticatorImpl.removeKey(forIdentifier: aCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: bCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: cCar.id)
      try? CarAuthenticatorImpl.removeKey(forIdentifier: dCar.id)
    }

    // Generate an advertisement that matches none of our cars.
    // 1) Generate a random eight byte salt and zero-pad it to sixteen bytes.
    // 2) Compute the HMAC for the padded salt and truncate it to three bytes.
    // 3) The advertisement is the truncated HMAC followed by the salt.
    let salt = CarAuthenticatorImpl.randomSalt(size: 8)
    let paddedSalt = Array(salt) + Array(repeating: 0, count: 8)
    let paddedSaltData = Data(bytes: paddedSalt, count: paddedSalt.count)
    let hmac = CarAuthenticatorImpl().computeHMAC(data: paddedSaltData)
    let advertisement = Data(hmac[0..<3] + salt)
    XCTAssertEqual(advertisement.count, 11)

    let match = CarAuthenticatorImpl.first(among: cars, matchingData: advertisement)
    XCTAssertNil(match)
  }

  func testChallengeAuthenticationSuccess() {
    let sourceAuthenticator = CarAuthenticatorImpl()
    let salt = CarAuthenticatorImpl.randomSalt(size: 8)
    let hmac = sourceAuthenticator.computeHMAC(data: salt)

    // Authentication should succeed using the same key.
    let authenticator = try! CarAuthenticatorImpl(keyData: sourceAuthenticator.keyData)
    let result = authenticator.isMatch(challenge: salt, hmac: hmac)
    XCTAssertTrue(result)
  }

  func testChallengeAuthenticationFailure() {
    let sourceAuthenticator = CarAuthenticatorImpl()
    let salt = CarAuthenticatorImpl.randomSalt(size: 8)
    let hmac = sourceAuthenticator.computeHMAC(data: salt)

    // Authentication should fail using an unrelated authenticator.
    let authenticator = CarAuthenticatorImpl()
    let result = authenticator.isMatch(challenge: salt, hmac: hmac)
    XCTAssertFalse(result)
  }

  // MARK: - Private Helper Methods

  private func randomData(count: Int) -> Data {
    let bytes = (0..<count).map { _ in UInt8.random(in: 0...UInt8.max) }
    return Data(bytes: bytes, count: bytes.count)
  }
}
