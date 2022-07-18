// Copyright 2022 Google LLC
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

/// Unit tests for AnyOutOfBandTokenProvider.
@available(watchOS 6.0, *)
class AnyOutOfBandTokenProviderTest: XCTestCase {
  // The token provider to test.
  private var testWrapper: AnyOutOfBandTokenProvider!
  private var mockProvider: MockOutOfBandTokenProvider!

  override func setUp() {
    super.setUp()

    mockProvider = MockOutOfBandTokenProvider()
    testWrapper = AnyOutOfBandTokenProvider(source: mockProvider)
  }

  override func tearDown() {
    mockProvider = nil
    testWrapper = nil

    super.tearDown()
  }

  func testCallsPrepareForRequestOnProviders() {
    testWrapper.prepareForRequests()

    XCTAssertTrue(mockProvider.prepareForRequestsCalled)
  }

  func testCallsCloseForRequestOnProviders() {
    testWrapper.closeForRequests()

    XCTAssertTrue(mockProvider.closeForRequestsCalled)
  }

  func testCallsResetOnProviders() {
    testWrapper.reset()

    XCTAssertTrue(mockProvider.resetCalled)
  }

  func testForwardsTokenPosted() {
    testWrapper.closeForRequests()

    var token: OutOfBandToken? = nil
    testWrapper.requestToken {
      token = $0
    }

    XCTAssertNil(token)

    mockProvider.postToken(FakeOutOfBandToken())
    XCTAssertNotNil(token)
  }
}

/// Fake Out of Band token with minimal implementation.
@available(watchOS 6.0, *)
private struct FakeOutOfBandToken: OutOfBandToken {
  /// Encrypt the message by reversing it.
  func encrypt(_ message: Data) throws -> Data {
    Data(message.reversed())
  }

  /// Decrypt the message by reversing it.
  func decrypt(_ message: Data) throws -> Data {
    Data(message.reversed())
  }
}
