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

@testable import AndroidAutoMessageStream

/// Unit tests for `MessageIDGenerator`.
class MessageIDGeneratorTest: XCTestCase {
  func testNextMessageID_correctlyIncrements() {
    let messageIDGenerator = MessageIDGenerator.shared
    let initialMessageID = messageIDGenerator.next()

    XCTAssertEqual(messageIDGenerator.next(), initialMessageID + 1)
  }

  func testNextMessageID_correctlyWrapsBackToZero() {
    let messageIDGenerator = MessageIDGenerator.shared
    messageIDGenerator.messageID = Int32.max

    XCTAssertEqual(messageIDGenerator.next(), Int32.max)

    // This next ID should have been wrapped back to 0.
    XCTAssertEqual(messageIDGenerator.next(), 0)
  }
}
