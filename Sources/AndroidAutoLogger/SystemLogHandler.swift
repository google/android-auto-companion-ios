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
import os.log

/// Handler which feeds the logs to system log using os_log.
@available(macOS 10.15, *)
public class SystemLogHandler: LoggerDelegate {
  /// Log the record to the system log.
  ///
  /// Messages for public logs will be tagged "%{public}s". The record level will be mapped to the
  /// corresponding OSLogType.
  ///
  /// - Parameter record: The record to log.
  public func loggerDidRecordMessage(_ record: LogRecord) {
    let logType = record.level.osLogType
    let log: OSLog
    if let subsystem = record.subsystem, let category = record.category {
      log = OSLog(subsystem: subsystem, category: category)
    } else {
      log = OSLog.default
    }

    switch record.redactableMessage {
    case .some(let redactableMessage):
      // Output primary message followed by the redactable message.
      os_log("%{public}s %s", log: log, type: logType, record.message, redactableMessage)
    case .none:
      os_log("%{public}s", log: log, type: logType, record.message)
    }
  }
}

/// System log extensions for Logger.Level.
@available(macOS 10.15, *)
extension Logger.Level {
  /// Get the corresponding `OSLogType`.
  var osLogType: OSLogType {
    switch self {
    case .debug: return .debug
    case .info: return .info
    case .standard: return .default
    case .error: return .error
    case .fault: return .fault
    }
  }
}
