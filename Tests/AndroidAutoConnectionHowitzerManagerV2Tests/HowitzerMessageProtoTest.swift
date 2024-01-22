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

import Foundation
import SwiftProtobuf
import XCTest
@_implementationOnly import AndroidAutoConnectionHowitzerV2Protos

@testable import AndroidAutoConnectionHowitzerManagerV2

typealias Timestamp = Google_Protobuf_Timestamp

class HowitzerMessageProtoTest: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  func testConfigProtoFromConfig() {
    let testID = UUID()
    let config = HowitzerConfig(payloadSize: 900, payloadCount: 100, sentFromIHU: true)

    var expectedProto = HowitzerConfigProto()
    expectedProto.testID = testID.uuidString.lowercased()
    expectedProto.payloadSize = 900
    expectedProto.payloadCount = 100
    expectedProto.sendPayloadFromIhu = true

    XCTAssertEqual(expectedProto, HowitzerConfigProto(testID: testID, config: config))
  }

  func testConfigMessageProto() {
    let testID = UUID()
    let config = HowitzerConfig(payloadSize: 900, payloadCount: 100, sentFromIHU: true)

    var expectedProto = HowitzerMessageProto()
    expectedProto.messageType = HowitzerMessageProto.MessageType.config
    expectedProto.config = HowitzerConfigProto(testID: testID, config: config)

    XCTAssertEqual(expectedProto, HowitzerMessageProto(testID: testID, config: config))
  }

  func testAckMessageProto() {
    var expectedProto = HowitzerMessageProto()
    expectedProto.messageType = HowitzerMessageProto.MessageType.ack

    XCTAssertEqual(expectedProto, HowitzerMessageProto(type: HowitzerMessageProto.MessageType.ack))
  }

  func testMessageProtoFromResult() {
    let testID = UUID()
    let config = HowitzerConfig(payloadSize: 900, payloadCount: 1, sentFromIHU: true)
    let isValid = true
    let testStartTime = Date().timeIntervalSince1970
    let payloadReceivedTimestamps = [Date().timeIntervalSince1970]
    let result = HowitzerResult(
      isValid: isValid,
      payloadReceivedTimestamps: payloadReceivedTimestamps,
      testStartTime: testStartTime)

    var expectedProto = HowitzerMessageProto()
    expectedProto.messageType = HowitzerMessageProto.MessageType.result
    expectedProto.config = HowitzerConfigProto(testID: testID, config: config)
    expectedProto.result = HowitzerResultProto(result: result)

    XCTAssertEqual(
      expectedProto,
      HowitzerMessageProto(testID: testID, config: config, result: result))
  }

  func testResultMessageProto() {
    let isValid = true
    let testStartTime = Date().timeIntervalSince1970
    let testStartTimestamp = Timestamp(timeIntervalSince1970: testStartTime)
    let payloadReceivedTimeIntervals = [testStartTime]
    let payloadReceivedTimestamps = [testStartTimestamp]
    let result = HowitzerResult(
      isValid: isValid,
      payloadReceivedTimestamps: payloadReceivedTimeIntervals,
      testStartTime: testStartTime
    )

    var expectedProto = HowitzerResultProto()
    expectedProto.isValid = isValid
    expectedProto.testStartTimestamp = testStartTimestamp
    expectedProto.payloadReceivedTimestamps = payloadReceivedTimestamps

    XCTAssertEqual(
      expectedProto,
      HowitzerResultProto(result: result))
  }
}
