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

import Foundation

/// Utils for logging mock.
enum LoggingMockUtils {
  /// Get the date components for the given date which correspond to a day.
  static func dayComponentsForDate(_ date: Date) -> DateComponents {
    let calendar = Calendar(identifier: .gregorian)
    return calendar.dateComponents([.year, .month, .day], from: date)
  }
}
