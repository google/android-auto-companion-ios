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
@available(watchOS 6.0, *)
class CoalescingOutOfBandTokenProviderTest: XCTestCase {
  // The token provider to test.
  private var testTokenProvider: CoalescingOutOfBandTokenProvider<MockOutOfBandTokenProvider>!

  override func setUp() {
    super.setUp()

    testTokenProvider = CoalescingOutOfBandTokenProvider()
  }

  override func tearDown() {
    testTokenProvider = nil

    super.tearDown()
  }

  func testNoChildProviders_BailsImmediately() {
    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testRegistersProvider() {
    let child = MockOutOfBandTokenProvider()
    testTokenProvider.register(child)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    child.postToken(FakeOutOfBandToken())

    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testCallsPrepareForRequestOnProviders() {
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2)

    testTokenProvider.prepareForRequests()

    XCTAssertTrue(child1.prepareForRequestsCalled)
    XCTAssertTrue(child2.prepareForRequestsCalled)
  }

  func testCallsCloseForRequestOnProviders() {
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2)

    testTokenProvider.closeForRequests()

    XCTAssertTrue(child1.closeForRequestsCalled)
    XCTAssertTrue(child2.closeForRequestsCalled)
  }

  func testCallsResetOnProviders() {
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    testTokenProvider = CoalescingOutOfBandTokenProvider(child1, child2)

    testTokenProvider.reset()

    XCTAssertTrue(child1.resetCalled)
    XCTAssertTrue(child2.resetCalled)
  }

  /// Only providers registered before a request should service the request for predictable behavior
  /// (i.e. the completion handler should be called exactly once per request).
  func testIgnoresProviderRegisteredAfterRequest() {
    let child1 = MockOutOfBandTokenProvider()
    testTokenProvider.register(child1)

    var tokenCounter = 0
    var token: OutOfBandToken? = nil
    testTokenProvider.requestToken {
      token = $0
      tokenCounter += 1
    }

    // Child 2 was registered after the request, so the request should ignore it.
    let child2 = MockOutOfBandTokenProvider()
    testTokenProvider.register(child2)
    child2.postToken(FakeOutOfBandToken())

    XCTAssertNil(token)
    XCTAssertEqual(tokenCounter, 0)

    // Child 1 was registered before the request, so it fulfills the request.
    child1.postToken(FakeOutOfBandToken())
    XCTAssertNotNil(token)
    XCTAssertEqual(tokenCounter, 1)
  }

  func testForwardsChildTokenPosted() {
    let child = MockOutOfBandTokenProvider()
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
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    let child3 = MockOutOfBandTokenProvider()
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
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    let child3 = MockOutOfBandTokenProvider()
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
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    let child3 = MockOutOfBandTokenProvider()
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
    let child1 = MockOutOfBandTokenProvider()
    let child2 = MockOutOfBandTokenProvider()
    let child3 = MockOutOfBandTokenProvider()
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

/// Mock Out-Of-Band Token Provider.
@available(watchOS 6.0, *)
class MockOutOfBandTokenProvider: OutOfBandTokenProvider {
  private var completion: ((OutOfBandToken?) -> Void)?
  private var token: OutOfBandToken? = nil

  var prepareForRequestsCalled = false
  var closeForRequestsCalled = false
  var resetCalled = false

  func prepareForRequests() {
    prepareForRequestsCalled = true
  }

  func closeForRequests() {
    closeForRequestsCalled = true
  }

  func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
    if let token = token {
      completion(token)
    } else {
      self.completion = completion
    }
  }

  func reset() {
    resetCalled = true
    token = nil
    completion?(nil)
    completion = nil
  }

  func postToken(_ token: OutOfBandToken?) {
    self.token = token
    completion?(token)
    completion = nil
  }

  init() {}
}
