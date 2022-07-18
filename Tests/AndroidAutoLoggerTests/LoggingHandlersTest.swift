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

/// Unit tests for `LoggingHandlers`.

class LoggingHandlersTest: XCTestCase {
  func testSharedIsStandard() {
    XCTAssertTrue(LoggingHandlers.shared === LoggingHandlers.standard)
  }
}

/// Unit tests for `CompoundLogHandler`.

class CompoundLogHandlerTest: XCTestCase {
  public func testForwardingToChildHandlers() {
    let mockChild1 = LogHandlerMock()
    let mockChild2 = LogHandlerMock()
    let handler = CompoundLogHandler(handlers: [mockChild1, mockChild2])
    let logger = Logger.default.delegate(handler)

    XCTAssertFalse(mockChild1.didLogRecord)
    XCTAssertFalse(mockChild2.didLogRecord)

    logger.log("Test")

    XCTAssertTrue(mockChild1.didLogRecord)
    XCTAssertTrue(mockChild2.didLogRecord)
  }
}

/// Mock for testing handler calls.

class LogHandlerMock: LoggerDelegate {
  var didLogRecord = false

  func loggerDidRecordMessage(_ record: LogRecord) {
    didLogRecord = true
  }
}
