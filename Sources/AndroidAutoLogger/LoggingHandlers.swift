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

/// Provides the standard log handlers which implement LoggerDelegate.
@available(macOS 10.15, *)
public struct LoggingHandlers {
  /// Compound handler that feeds the standard log handlers.
  static let standard: LoggerDelegate = {
    return CompoundLogHandler(handlers: [Self.system, Self.archiver])
  }()

  /// Shared handler which is what the loggers use by default.
  ///
  /// In the future we may want to make this configurable, but by default it will be set to the
  /// standard.
  public static let shared: LoggerDelegate = LoggingHandlers.standard

  /// Logs just to the system log.
  public static let system = SystemLogHandler()

  /// Logs just to our custom archiver.
  public static let archiver = LogArchiver()
}

/// Log handler which feeds logs to its child log handlers.
///
/// This log handler is thread safe, but it does not guarantee that its child log handlers are, so
/// it is only as thread safe as its children are collectively.
@available(macOS 10.15, *)
public class CompoundLogHandler: LoggerDelegate {
  /// Child handlers.
  private let handlers: [LoggerDelegate]

  /// Initializer with the array of child handlers.
  ///
  /// - Parameter handlers: The child handlers.
  init(handlers: [LoggerDelegate]) {
    self.handlers = handlers
  }

  /// Feed the record to the child handlers for processing.
  ///
  /// - Parameter record: The record to process.
  public func loggerDidRecordMessage(_ record: LogRecord) {
    for handler in handlers {
      handler.loggerDidRecordMessage(record)
    }
  }
}
