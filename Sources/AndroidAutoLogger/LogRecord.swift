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

/// `LogRecord` is a snapshot for a log message.
///
/// All properties are values captured when the snapshot was recorded.
@available(macOS 10.15, *)
@dynamicMemberLookup
public struct LogRecord {
  /// The logger which recorded this record.
  let logger: Logger

  /// The time when the snapshot was recorded.
  let timestamp: Date

  /// The timezone when the snapshot was recorded.
  let timezone: TimeZone

  /// The process identifier.
  let processId: Int32  // Type matches ProcessInfo.processIdentifier.

  /// The name of the process.
  let processName: String

  /// The thread on which the logger was called to record the message.
  let threadId: Int

  /// The source file where the logger was called to record the message.
  let file: String

  /// The line in the source file where the logger was called to record the message.
  let line: Int

  /// The function in which the logger was called to record the message.
  let function: String

  /// Optional stack trace symbols provided for fault logs.
  let backTrace: [String]?

  /// The message that was specified to be logged.
  let message: String

  /// Optional message to be redacted and appended after the primary message in output.
  let redactableMessage: String?

  /// Optional, custom metadata.
  let metadata: [String: LogMetaData]?

  /// Surface the logger properties to this record.
  public subscript<T>(dynamicMember keyPath: KeyPath<Logger, T>) -> T {
    logger[keyPath: keyPath]
  }
}

// MARK - Implement `Encodable` conformance.
@available(macOS 10.15, *)
extension LogRecord: Encodable {
  /// Coding keys for the record's properties.
  enum CodingKeys: String, CodingKey {
    case timestamp
    case processId
    case processName
    case threadId
    case file
    case line
    case function
    case backTrace
    case message
    case subsystem
    case category
    case level
    case metadata
  }

  /// Encode the record to the specified encoder.
  ///
  /// Note that to respect privacy, `redactableMessage` will not be encoded.
  /// - Parameter encoder: The encoder to which to encode the record.
  /// - Throws: An error if a property fails to be encoded.
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(timestamp.encodeForLog(timezone: timezone), forKey: .timestamp)
    try container.encode(processId, forKey: .processId)
    try container.encode(processName, forKey: .processName)
    try container.encode(threadId, forKey: .threadId)
    try container.encode(file, forKey: .file)
    try container.encode(line, forKey: .line)
    try container.encode(function, forKey: .function)
    try container.encode(backTrace, forKey: .backTrace)
    try container.encode(message, forKey: .message)
    try container.encode(self.subsystem, forKey: .subsystem)
    try container.encode(self.category, forKey: .category)
    try container.encode(self.level, forKey: .level)

    if let metadata = metadata {
      var metadataContainer = container.nestedContainer(
        keyedBy: MetadataCodingKey.self, forKey: .metadata)
      try encodeMetadata(metadata, to: &metadataContainer)
    }
  }
}

// MARK - Encode timestamp.
extension Date {
  /// Encode a timestamp to a string which includes the date, time with milliseconds and the
  /// timezone offset from UTC.
  ///
  /// Generates an econding formatted such as: "2020-06-26T10:06:41.363-0700".
  ///
  /// - Parameter timezone: The timezone to output in the encoding.
  /// - Returns: The encoded timestamp.
  func encodeForLog(timezone: TimeZone) -> String {
    // See: https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    formatter.timeZone = timezone

    return formatter.string(from: self)
  }
}
