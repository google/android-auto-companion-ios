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

internal import AndroidAutoLogger
internal import XCTest

/// Mock `PersistentLogStore`
class MockLogStore: PersistentLogStore {
  var writeRecordExpectation: XCTestExpectation?
  var appendDataExpectation: XCTestExpectation?

  let date: Date

  init(date: Date) {
    self.date = date
  }

  /// Returns `true` if the specified date represents the same day as this archive's date in GMT.
  ///
  /// - Parameter date: The date with which to compare.
  func canLogDate(_ date: Date) -> Bool {
    let calendar = Calendar(identifier: .gregorian)
    let yearMonthDay = LoggingMockUtils.dayComponentsForDate(self.date)
    return calendar.date(date, matchesComponents: yearMonthDay)
  }

  /// Write the specified record to the log file.
  ///
  /// - Parameter record: The log record to append.
  func writeRecord(_ record: LogRecord) {
    writeRecordExpectation?.fulfill()
  }

  /// Append the data to the log file.
  ///
  /// - Parameter data: The data to append.
  func appendData(_ data: Data) {
    appendDataExpectation?.fulfill()
  }
}
