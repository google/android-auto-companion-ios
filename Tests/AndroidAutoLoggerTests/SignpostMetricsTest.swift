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

class SignpostMetricsTest: XCTestCase {
  func testIsAvailable() {
    XCTAssertTrue(SignpostMetrics.isSystemSupported)
  }

  func testPost_CallsHandler() {
    let handler = SignpostMetricsHandlerMock(category: "Test")
    let metrics = SignpostMetrics(handler: handler)
    let marker = SignpostMarker("Test")

    metrics.post(marker)

    XCTAssertTrue(handler.postCalled)
  }

  func testPostIfAvailable_CallsHandler_isAvailable() {
    let handler = SignpostMetricsHandlerMock(category: "Test")
    handler.isValid = true

    let metrics = SignpostMetrics(handler: handler)
    let marker = SignpostMarker("Test")

    metrics.postIfAvailable(marker)

    XCTAssertTrue(handler.postCalled)
  }

  func testPostIfAvailable_DoesNotCallHandler_isNotAvailable() {
    let handler = SignpostMetricsHandlerMock(category: "Test")
    handler.isValid = false

    let metrics = SignpostMetrics(handler: handler)
    let marker = SignpostMarker("Test")

    metrics.postIfAvailable(marker)

    XCTAssertFalse(handler.postCalled)
  }
}

private class SignpostMetricsHandlerMock: SignpostMetricsHandler {
  let category: String
  var isValid = false

  private(set) var postCalled = false

  required init(category: String) {
    self.category = category
  }

  func post(_ marker: SignpostMarker, dso: UnsafeRawPointer) {
    postCalled = true
  }
}
