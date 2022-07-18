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

/// Unit tests for PassiveOutOfBandTokenProvider.
@available(watchOS 6.0, *)
class PassiveOutOfBandTokenProviderTest: XCTestCase {
  // The token provider to test.
  private var testTokenProvider: PassiveOutOfBandTokenProvider!

  override func setUp() {
    super.setUp()

    testTokenProvider = PassiveOutOfBandTokenProvider()
  }

  override func tearDown() {
    testTokenProvider = nil

    super.tearDown()
  }

  func testCallsCompletionWithNoToken() {
    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testForwardsPostedToken() {
    testTokenProvider.postToken(FakeOutOfBandToken())

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testResetClearsToken() {
    testTokenProvider.postToken(FakeOutOfBandToken())
    testTokenProvider.reset()

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }
}

/// Fake Out of Band token with minimal implementation.
private struct FakeOutOfBandToken: OutOfBandToken {
  /// Encrypt the message by reversing it.
  func encrypt(_ message: Data) throws -> Data {
    message
  }

  /// Decrypt the message by reversing it.
  func decrypt(_ message: Data) throws -> Data {
    message
  }
}
