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

@testable import AndroidAutoConnectionHowitzerManagerV2

/// A mock `ConnectionHowitzerManagerV2Delegate` that can assert if its methods are called.
public class ConnectionHowitzerManagerV2DelegateMock: ConnectionHowitzerManagerV2Delegate {
  public var onTestCompletedSuccessfully = false
  public var onTestFailed = false

  public func connectionHowitzerManagerV2(
    _ connectionHowitzerManagerV2: ConnectionHowitzerManagerV2,
    testConfig config: HowitzerConfig,
    testCompletedResult result: HowitzerResult
  ) {
    if result.isValid {
      onTestCompletedSuccessfully = true
    } else {
      onTestFailed = true
    }
  }
}
