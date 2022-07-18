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

import AndroidAutoLogger
import XCTest

/// Mock `PersistentLogStoreFactory`
public class MockLogStoreFactory: PersistentLogStoreFactory {
  public var makeStoreExpectation: XCTestExpectation?

  public var appendDataStore: MockLogStore?
  public var appendDataExpectation: XCTestExpectation?

  /// Store keyed by the date components.
  public var stores: [DateComponents: MockLogStore] = [:]

  /// Expectations to use for stores.
  public var writeRecordExpectations: [DateComponents: XCTestExpectation] = [:]

  public init() {}

  public func makeStore(directory: String, date: Date, carName: String?) -> PersistentLogStore {
    let dayComponents = LoggingMockUtils.dayComponentsForDate(date)

    let store = MockLogStore(date: date)

    if carName != nil {
      appendDataStore = store
      store.appendDataExpectation = appendDataExpectation
    } else {
      stores[dayComponents] = store
      if let writeRecordExpectation = writeRecordExpectations[dayComponents] {
        store.writeRecordExpectation = writeRecordExpectation
      }
    }

    makeStoreExpectation?.fulfill()

    return store
  }

  public func storeForDate(_ date: Date) -> MockLogStore? {
    let dayComponents = LoggingMockUtils.dayComponentsForDate(date)
    return stores[dayComponents]
  }

  public func setWriteRecordExpectation(_ expectation: XCTestExpectation, for date: Date) {
    let dayComponents = LoggingMockUtils.dayComponentsForDate(date)
    writeRecordExpectations[dayComponents] = expectation
  }
}
