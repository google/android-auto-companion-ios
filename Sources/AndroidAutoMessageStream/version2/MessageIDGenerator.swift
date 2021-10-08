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

/// A generator of unique IDs for messages.
///
/// This class is not thread-safe.
class MessageIDGenerator {
  static let shared = MessageIDGenerator()

  /// An ID that can be used to uniquely identify a message.
  ///
  /// This value should always be positive.
  ///
  /// It is exposed for testing purposes. Use `next()` to retrieve the correct value to use.
  var messageID: Int32 = 0

  /// Returns a new, unique ID for identifying messages.
  ///
  /// This method is not thread-safe.
  func next() -> Int32 {
    let currentMessageID = messageID

    if messageID == Int32.max {
      // The ID cannot be negative, so reset to 0.
      messageID = 0
    } else {
      messageID += 1
    }

    return currentMessageID
  }

  /// Resets the message ID back to its default value.
  ///
  /// This method is exposed for testing purposes and should not be called during regular logic
  /// flows.
  func reset() {
    messageID = 0
  }
}
