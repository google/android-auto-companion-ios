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

/// Unit tests for CoalescingOutOfBandTokenProvider.
@available(iOS 10.0, watchOS 6.0, *)
class CoalescingOutOfBandTokenProviderTest: XCTestCase {
  // The token provider to test.
  private var testTokenProvider: CoalescingOutOfBandTokenProvider!

  override func setUp() {
    super.setUp()

    testTokenProvider = CoalescingOutOfBandTokenProvider()
  }

  override func tearDown() {
    testTokenProvider = nil

    super.tearDown()
  }

  func testNoChildProviders_BailsImmediately() {
    testTokenProvider = CoalescingOutOfBandTokenProvider()

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testForwardsChildTokenPosted() {
    let child = FakeOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    child.postToken(FakeOutOfBandToken())
    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testForwardsFirstNonNilChildTokenPosted() {
    let child1 = FakeOutOfBandTokenProvider()
    let child2 = FakeOutOfBandTokenProvider()
    let child3 = FakeOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2, child3)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    child1.reset()
    child2.postToken(FakeOutOfBandToken())
    child3.reset()
    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testCallsCompletionOnlyOnce() {
    let child1 = FakeOutOfBandTokenProvider()
    let child2 = FakeOutOfBandTokenProvider()
    let child3 = FakeOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2, child3)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    child1.postToken(FakeOutOfBandToken())
    child2.postToken(FakeOutOfBandToken())
    child3.postToken(FakeOutOfBandToken())
    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testCallsCompletionIfNoTokensDiscovered() {
    let child1 = FakeOutOfBandTokenProvider()
    let child2 = FakeOutOfBandTokenProvider()
    let child3 = FakeOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2, child3)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    child1.postToken(nil)
    child2.postToken(nil)
    child3.postToken(nil)
    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testCallsCompletionOnReset() {
    let child1 = FakeOutOfBandTokenProvider()
    let child2 = FakeOutOfBandTokenProvider()
    let child3 = FakeOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2, child3)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    testTokenProvider.reset()
    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }
}

/// Fake Out of Band token with minimal implementation.
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
