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

private import AndroidAutoLogger
internal import Foundation

/// Calculate bandwidth test analytics.
public struct BandwidthCalculator {
  /// Config of the bandwidth test.
  let config: HowitzerConfig
  /// Result of the bandwidth test
  let result: HowitzerResult

  /// BandwidthCalculator errors.
  enum Error: Swift.Error {
    case invalidInput
  }

  private static let log = Logger(for: BandwidthCalculator.self)

  public init(config: HowitzerConfig, result: HowitzerResult) {
    self.config = config
    self.result = result
  }

  /// Average bandwidth in bytes/s.
  public var averageBandwidth: Double {
    get throws {
      guard
        validateResultParameters(),
        let testEndTime = result.payloadReceivedTimestamps.last,
        case let duration = testEndTime - result.testStartTime,
        duration > 0
      else {
        Self.log.error("Invalid parameters. Cannot calculate average bandwidth.")
        throw Error.invalidInput
      }

      return Double(config.payloadCount * config.payloadSize) / duration
    }
  }

  private func validateResultParameters() -> Bool {
    return config.payloadSize > 0 && result.isValid
      && config.payloadCount == result.payloadReceivedTimestamps.count
  }
}
