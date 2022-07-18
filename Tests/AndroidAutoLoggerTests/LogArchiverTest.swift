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

@testable import AndroidAutoLogger

/// Unit tests for `LogArchiver`.

class LogArchiverTest: XCTestCase {
  private let logger = Logger(for: LogArchiverTest.self)

  private var archiver: LogArchiver!
  private var storeFactory: MockLogStoreFactory!

  override func setUp() {
    super.setUp()

    storeFactory = MockLogStoreFactory()
    archiver = LogArchiver(persistentStoreFactory: storeFactory)
  }

  func testLogMakesStoreCall() {
    let makeStoreExpectation = XCTestExpectation(description: "Store Factory Makes Store")
    storeFactory.makeStoreExpectation = makeStoreExpectation

    let writeRecordExpectation = XCTestExpectation(description: "Write Record")

    let date = Date()
    storeFactory.setWriteRecordExpectation(writeRecordExpectation, for: date)

    let record = makeLogRecord(logger: logger, date: date)
    archiver.loggerDidRecordMessage(record)

    wait(for: [makeStoreExpectation, writeRecordExpectation], timeout: 2)

    XCTAssertNotNil(storeFactory.storeForDate(date))
  }

  func testMultipleLogsWithSameDateShareSameStore() {
    let makeStoreExpectation = XCTestExpectation(description: "Store Factory Makes Store")
    makeStoreExpectation.expectedFulfillmentCount = 1
    makeStoreExpectation.assertForOverFulfill = true
    storeFactory.makeStoreExpectation = makeStoreExpectation

    let writeRecordExpectation = XCTestExpectation(description: "Write Record")

    let date = Date()
    let logCount = 7

    storeFactory.setWriteRecordExpectation(writeRecordExpectation, for: date)
    writeRecordExpectation.expectedFulfillmentCount = logCount

    for _ in 1...logCount {
      let record = makeLogRecord(logger: logger, date: date)
      archiver.loggerDidRecordMessage(record)
    }

    wait(for: [makeStoreExpectation, writeRecordExpectation], timeout: 2)

    XCTAssertEqual(storeFactory.stores.count, 1)
    XCTAssertNotNil(storeFactory.storeForDate(date))
  }

  func testLogsForDifferentDatesMakeDifferentStores() {
    let makeStoreExpectation = XCTestExpectation(description: "Store Factory Makes Store")
    makeStoreExpectation.expectedFulfillmentCount = 2
    makeStoreExpectation.assertForOverFulfill = true
    storeFactory.makeStoreExpectation = makeStoreExpectation

    let today = Date()
    let todayWriteRecordExpectation = XCTestExpectation(description: "Today Write Record")
    storeFactory.setWriteRecordExpectation(todayWriteRecordExpectation, for: today)

    let tomorrow = today.addingTimeInterval(1 * 24 * 3_600)
    let tomorrowWriteRecordExpectation = XCTestExpectation(description: "Tomorrow Write Record")
    storeFactory.setWriteRecordExpectation(tomorrowWriteRecordExpectation, for: tomorrow)

    let record1 = makeLogRecord(logger: logger, date: today)
    archiver.loggerDidRecordMessage(record1)
    let record2 = makeLogRecord(logger: logger, date: tomorrow)
    archiver.loggerDidRecordMessage(record2)

    wait(
      for: [makeStoreExpectation, todayWriteRecordExpectation, tomorrowWriteRecordExpectation],
      timeout: 2
    )
  }

  /// Helper function to make a log record.
  private func makeLogRecord(logger: Logger, date: Date) -> LogRecord {
    return LogRecord(
      logger: logger,
      timestamp: date,
      timezone: TimeZone.current,
      processId: 0,
      processName: "Test",
      threadId: 0,
      file: "Test",
      line: 0,
      function: "",
      backTrace: nil,
      message: "Test",
      redactableMessage: nil,
      metadata: nil
    )
  }
}
