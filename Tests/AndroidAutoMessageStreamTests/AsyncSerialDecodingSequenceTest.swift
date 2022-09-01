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

@testable import AndroidAutoMessageStream

/// Unit tests for `AsyncSerialDecodingSequence`.
class AsyncSerialDecodingSequenceTest: XCTestCase {
  private var sequence: AsyncSerialDecodingSequence<MockSerialDecodingAdaptor>!
  private var mockAdaptor: MockSerialDecodingAdaptor!

  override func setUp() {
    super.setUp()
    continueAfterFailure = false

    mockAdaptor = MockSerialDecodingAdaptor()
    sequence = AsyncSerialDecodingSequence(mockAdaptor)
  }

  override func tearDown() {
    sequence = nil
    mockAdaptor = nil

    super.tearDown()
  }

  func testStartDecodingCalled() {
    XCTAssertTrue(mockAdaptor.startDecodingCalled)
  }

  func testDecodingNilCallsStopDecoding() {
    XCTAssertFalse(mockAdaptor.stopDecodingCalled)

    mockAdaptor.terminate()
    XCTAssertTrue(mockAdaptor.stopDecodingCalled)
  }

  func testSingleDecoding() async throws {
    mockAdaptor.post(1)
    let result = try await sequence.next()

    XCTAssertNotNil(result)
    XCTAssertEqual(1, result)
  }

  func testPreElementsDecoded() async throws {
    let input = [2, 3, 5]

    input.forEach {
      mockAdaptor.post($0)
    }
    mockAdaptor.terminate()

    let results: [Int] = try await sequence.reduce(into: []) { aggregate, value in
      aggregate.append(value)
    }

    XCTAssertFalse(results.isEmpty)
    XCTAssertEqual(results.count, input.count)
    XCTAssertEqual(results, input)
  }

  func testElementsDecoded() async throws {
    let input = [2, 3, 5]
    Task {
      input.forEach {
        mockAdaptor.post($0)
      }
      mockAdaptor.terminate()
    }

    let results: [Int] = try await sequence.reduce(into: []) { aggregate, value in
      aggregate.append(value)
    }

    XCTAssertFalse(results.isEmpty)
    XCTAssertEqual(results.count, input.count)
    XCTAssertEqual(results, input)
  }

  func testThrowsErrorForwardedFromAdaptor() async {
    enum FakeError: Error {
      case fake
    }

    mockAdaptor.post(FakeError.fake)

    do {
      let _ = try await sequence.next()
      XCTFail("Should have thrown fake error, but no error thrown.")
    } catch FakeError.fake {
      // expected
    } catch {
      XCTFail("Unexpected error thrown: \(error)")
    }
  }
}

// MARK: - Mocks

private class MockSerialDecodingAdaptor {
  private var onElementDecoded: ((Result<Int?, Error>) -> Void)?

  var startDecodingCalled = false
  var stopDecodingCalled = false

  func post(_ result: Result<Int?, Error>) {
    guard let onElementDecoded = self.onElementDecoded else { return }
    onElementDecoded(result)
  }

  func post(_ value: Int) {
    post(.success(value))
  }

  func post(_ error: Error) {
    post(.failure(error))
  }

  func terminate() {
    post(.success(nil))
  }
}

// MARK: - SerialDecodingAdaptor Conformance

extension MockSerialDecodingAdaptor: SerialDecodingAdaptor {
  /// Begin decoding elements from the data source.
  func startDecoding(onElementDecoded: @escaping (Result<Int?, Error>) -> Void) {
    startDecodingCalled = true
    self.onElementDecoded = onElementDecoded
  }

  /// Stop decoding elements from the data source.
  func stopDecoding() {
    stopDecodingCalled = true
  }
}
