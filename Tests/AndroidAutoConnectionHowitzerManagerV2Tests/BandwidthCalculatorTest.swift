// Copyright 2023 Google LLC
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

private import Foundation
internal import XCTest

@testable private import AndroidAutoConnectionHowitzerManagerV2

private typealias Error = BandwidthCalculator.Error

class BandwidthCalculatorTest: XCTestCase {
  @MainActor func testAverageBandwidth_invalidResult_throwError() {
    let config = HowitzerConfig()
    let result = HowitzerResult(
      isValid: false,
      payloadReceivedTimestamps: [],
      testStartTime: TimeInterval()
    )
    let calculator = BandwidthCalculator(config: config, result: result)

    XCTAssertThrowsError(try calculator.averageBandwidth) { error in
      XCTAssertEqual(error as! Error, Error.invalidInput)
    }
  }

  @MainActor func testAverageBandwidth_invalidPayloadSize_throwError() {
    let config = HowitzerConfig(payloadSize: 0, payloadCount: 1, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let testEndTime = TimeInterval(testStartTime + 0.5)
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [testEndTime],
      testStartTime: testStartTime
    )
    let calculator = BandwidthCalculator(config: config, result: result)

    XCTAssertThrowsError(try calculator.averageBandwidth) { error in
      XCTAssertEqual(error as! Error, Error.invalidInput)
    }
  }

  @MainActor func testAverageBandwidth_invalidPayloadCount_throwError() {
    let config = HowitzerConfig(payloadSize: 100, payloadCount: 0, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let testEndTime = TimeInterval(testStartTime + 0.5)
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [testEndTime],
      testStartTime: testStartTime
    )
    let calculator = BandwidthCalculator(config: config, result: result)

    XCTAssertThrowsError(try calculator.averageBandwidth) { error in
      XCTAssertEqual(error as! Error, Error.invalidInput)
    }
  }

  @MainActor func testAverageBandwidth_payloadCountAndResultMismatch_throwError() {
    let config = HowitzerConfig(payloadSize: 100, payloadCount: 2, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let testEndTime = TimeInterval(testStartTime + 0.5)
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [testEndTime],
      testStartTime: testStartTime
    )
    let calculator = BandwidthCalculator(config: config, result: result)

    XCTAssertThrowsError(try calculator.averageBandwidth) { error in
      XCTAssertEqual(error as! Error, Error.invalidInput)
    }
  }

  @MainActor func testAverageBandwidth_invalidTestEndTime_throwError() {
    let config = HowitzerConfig(payloadSize: 100, payloadCount: 1, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let testEndTime = TimeInterval(testStartTime - 0.5)
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [testEndTime],
      testStartTime: testStartTime
    )
    let calculator = BandwidthCalculator(config: config, result: result)

    XCTAssertThrowsError(try calculator.averageBandwidth) { error in
      XCTAssertEqual(error as! Error, Error.invalidInput)
    }
  }

  @MainActor func testAverageBandwidth_validParameters_singlePayload() {
    let config = HowitzerConfig(payloadSize: 75, payloadCount: 1, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [TimeInterval(testStartTime + 2)],
      testStartTime: testStartTime
    )

    // bandwidth should be 75 / 2 = 37.5
    let expectedBandwidth = 37.5
    let calculator = BandwidthCalculator(config: config, result: result)
    let bandwidth = try! calculator.averageBandwidth

    XCTAssertEqual(bandwidth, expectedBandwidth)
  }

  @MainActor func testAverageBandwidth_validParameters_multiPayloads() {
    let config = HowitzerConfig(payloadSize: 75, payloadCount: 2, sentFromIHU: true)
    let testStartTime = Date().timeIntervalSince1970
    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: [
        TimeInterval(testStartTime + 1.5), TimeInterval(testStartTime + 3),
      ],
      testStartTime: testStartTime
    )

    // bandwidth should be (75 * 2) / 3 = 50
    let expectedBandwidth = 50.0
    let calculator = BandwidthCalculator(config: config, result: result)
    let bandwidth = try! calculator.averageBandwidth

    XCTAssertEqual(bandwidth, expectedBandwidth)
  }
}
