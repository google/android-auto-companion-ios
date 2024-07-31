// Copyright 2024 Google LLC
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

internal import XCTest

@testable private import AndroidAutoUtils

/// Tests for `PropertyListStore`.
class PropertyListStoreTest: XCTestCase {
  private var store: MockPropertyListStore!

  override func setUp() {
    store = MockPropertyListStore()
  }

  override func tearDown() {
    store = nil
  }

  func testEmptyStoreNilSettings() {
    let test: DemoSettings? = store["test"]
    XCTAssertNil(test)
  }

  func testEmptyStoreReturnsDefault() {
    let control = DemoSettings()
    let test = store["test", default: control]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testRemoveValueForKey() {
    store["test"] = [2, 3, 5]

    store.removeValue(forKey: "test")
    let test: [Int]? = store["test"]

    XCTAssertNil(test)
  }

  func testStoreRetrieveIntArray() {
    let control = [1, 2, 4, 8, 16]
    store["test"] = control

    let test: [Int]? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveIntSet() {
    let control: Set = [1, 2, 4, 8, 16]
    store["test"] = control

    let test: Set<Int>? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveStringSet() {
    let control: Set = ["Hello", "World"]
    store["test"] = control

    let test: Set<String>? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveInfoSet() {
    let control: Set = [
      Info(name: "Alice", age: 10),
      Info(name: "Bob", age: 8),
    ]
    store["test"] = control

    let test: Set<Info>? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveStorable() {
    let control = DemoSettings(
      isEnabled: true,
      count: 5,
      amount: 3.14,
      label: "test",
      primes: [2, 3, 5, 7, 11]
    )
    store["test"] = control

    let test: DemoSettings? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveNestedValues() throws {
    let control = DemoSettings(
      isEnabled: true,
      count: 1,
      amount: 2.0,
      label: "test",
      primes: [2, 3, 5, 7],
      info: Info(name: "Test", age: 25)
    )
    store["test"] = control

    let test: DemoSettings = try XCTUnwrap(store["test"])

    XCTAssertNotNil(test.info)
    XCTAssertEqual(test.info, control.info)
    XCTAssertEqual(test, control)
  }

  func testStoreRetrieveMatchingSettings() {
    let control = DemoSettings(
      isEnabled: true,
      count: 1,
      amount: 2.0,
      label: "test",
      primes: [7, 11, 13, 17, 19]
    )
    store["test"] = control

    let other = DemoSettings(
      isEnabled: true,
      count: 2,
      amount: 5.0,
      label: "other"
    )
    store["other"] = other

    let test: DemoSettings? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, control)
    XCTAssertNotEqual(test, other)
  }

  func testUpdateDefaultValue() {
    store["test", default: 2] += 1

    let test: Int? = store["test"]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, 3)
  }

  func testGetWithReturnType() {
    store["test"] = 7

    let test = store["test", returning: Int.self]

    XCTAssertNotNil(test)
    XCTAssertEqual(test, 7)
  }
}

// MARK: - Demo PropertyListConvertible Type

/// Demo settings for testing storage and retrieval.
private struct DemoSettings: Equatable {
  var isEnabled = false
  var count = 0
  var amount = 0.0
  var label = ""
  var primes = [2, 3, 5, 7]
  var info: Info? = nil
}

extension DemoSettings: PropertyListConvertible {
  private enum Key: String {
    case isEnabled
    case count
    case amount
    case label
    case primes
    case info
  }

  func makePropertyListPrimitive() -> [String: Any] {
    var primitive: [String: Any] =
      [
        Key.isEnabled.rawValue: isEnabled,
        Key.count.rawValue: count,
        Key.amount.rawValue: amount,
        Key.label.rawValue: label,
        Key.primes.rawValue: primes,
      ]
    if let infoPrimitive = info?.makePropertyListPrimitive() {
      primitive[Key.info.rawValue] = infoPrimitive
    }
    return primitive
  }

  init(primitive: [String: Any]) throws {
    isEnabled = primitive[Key.isEnabled.rawValue] as? Bool ?? false
    count = primitive[Key.count.rawValue] as? Int ?? 0
    amount = primitive[Key.amount.rawValue] as? Double ?? 0.0
    label = primitive[Key.label.rawValue] as? String ?? ""
    primes = primitive[Key.primes.rawValue] as? [Int] ?? []
    if let infoPrimitive = primitive[Key.info.rawValue] as? Info.Primitive {
      self.info = try Info(primitive: infoPrimitive)
    }
  }
}

private struct Info: Equatable, Hashable {
  let name: String
  let age: Int

  init(name: String, age: Int) {
    self.name = name
    self.age = age
  }
}

extension Info: PropertyListConvertible {
  init(primitive: [String: Any]) throws {
    guard let name = primitive["name"] as? String else {
      throw PropertyListStoreError.malformedPrimitive("Missing name.")
    }
    guard let age = primitive["age"] as? Int else {
      throw PropertyListStoreError.malformedPrimitive("Missing age.")
    }
    self.init(name: name, age: age)
  }

  func makePropertyListPrimitive() -> [String: Any] {
    ["name": name, "age": age]
  }
}

// MARK: - Mock PropertyListStore

/// A mock key-value store.
private class MockPropertyListStore: PropertyListStore {
  private var storage: [String: Any] = [:]

  func clear() {
    storage = [:]
  }

  /// Access and set primitive convertible values by key in the store.
  subscript<T>(key: String) -> T? where T: PropertyListConvertible {
    get {
      guard let primitive = storage[key] as? T.Primitive else { return nil }
      do {
        return try T.init(primitive: primitive)
      } catch {
        print("Error instantiating \(T.self) from \(primitive): \(error.localizedDescription)")
        return nil
      }
    }

    set {
      storage[key] = newValue?.makePropertyListPrimitive()
    }
  }

  func removeValue(forKey key: String) {
    storage[key] = nil
  }
}
