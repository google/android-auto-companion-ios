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

import Dispatch

extension DispatchTimeInterval {
  /// Returns the equivalent representation of this `DispatchTimeInterval` in seconds
  ///
  /// If the given time interval is not provided in seconds, then a `fatalError` will occur.
  func toSeconds() -> Double {
    // Should only ever get defined in seconds.
    if case .seconds(let value) = self {
      return Double(value)
    }

    fatalError("This DispatchTimeInterval is not defined in seconds.")
  }
}
