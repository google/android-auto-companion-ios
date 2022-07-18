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

/// Delegate for handling logging events.
@available(macOS 10.15, *)
public protocol LoggerDelegate: AnyObject {
  /// The logger did record a message which means the delegate should process the record (e.g.
  /// persisting the record) according to its policy.
  ///
  /// - Parameter record: The record to process.
  func loggerDidRecordMessage(_ record: LogRecord)
}

/// `Logger` is the API for logging messages and metadata.
///
/// Instances can be used like functions to directly log message and metadata. This struct follows
/// the modifier pattern so modifiers may be used to return copies with modified properties. So,
/// effectively they can be considered like configurable functions.
@available(macOS 10.15, *)
public struct Logger {
  /// Default logger with no subsystem or category.
  static public let `default` = Logger()

  /// Subsystem for tagging a log entry (e.g. "com.your_company.some_module").
  public let subsystem: String?

  /// Category for tagging a log entry (e.g. "YourSmartMonitor", "YourGreatController").
  public let category: String?

  /// Logging level indicating the significance of the log.
  public private(set) var level: Level = .standard

  /// Indicates whether logs are printed to standard output in addition to the archive.
  public private(set) var prints = false

  /// Delegate which processes logged messages.
  weak var delegate: LoggerDelegate? = LoggingHandlers.shared

  /// `true` if the logger will process log messages based on its logging level.
  ///
  /// Calling a logger with a lower priority level than the cutoff will effectively be a NOOP.
  public var isLoggable: Bool {
    level >= Self.minLoggableLevel
  }

  // A compiler flag can be set to specify the minimum level for logging.
  static public var minLoggableLevel: Level {
    #if NDEBUG
      return .info
    #else
      return .debug
    #endif
  }

  /// Initializer for a logger with both a subsystem and a category.
  ///
  /// - Parameters:
  ///   - subsystem: Subsystem to be written to the log record.
  ///   - category: Category to be written to the log record.
  ///   - prints: `true` (defaults to `false`) to print to standard output besides archiving.
  public init(subsystem: String, category: String, prints: Bool = false) {
    self.subsystem = subsystem
    self.category = category
    self.prints = prints
  }

  /// Initializer for a logger with neither a subsystem or category.
  private init() {
    self.subsystem = nil
    self.category = nil
  }

  /// Log the message and optional metadata without specifying a function name.
  ///
  /// If specified, the `redacting` parameter will be appended after the primary message with a
  /// space in between.
  ///
  /// This call is intrinsic to what the logger does, so a logger instance is essentially
  /// just a configurable function. This feature is available in swift 5.2+.
  ///
  /// Note that the persistence of any information logged depends on the delegate. For example,
  /// metadata will only be persisted if the delegate supports it.
  ///
  /// The `file`, `line` and `function` are intended for internal use so they can capture the
  /// location of the call using the default parameter values. You shouldn't need to assign
  /// values to them. This works just as it does for standard Swift functions as in:
  /// https://developer.apple.com/documentation/swift/1539374-preconditionfailure
  /// Likewise, `backtraceOffset` is used internally to determine how far back to begin the
  /// back trace. You should not assign any value to it.
  ///
  /// - Parameters:
  ///   - message: The message to log.
  ///   - redacting: Option message to append that will be redacted when persisted.
  ///   - metadata: Optional structured data to support reporting and investigation.
  ///   - backtraceOffset: Optional backtrace offset for fault logs.
  ///   - file: Don't specify as the default parameter is used internally.
  ///   - line: Don't specify as the default parameter is used internally.
  ///   - function: Don't specify as the default parameter is used internally.
  public func callAsFunction(
    _ message: @autoclosure () -> String,
    redacting redactableMessage: @autoclosure () -> String? = nil,
    metadata: @autoclosure () -> [String: LogMetaData]? = nil,
    backtraceOffset: UInt = 0,
    file: String = #file,
    line: Int = #line,
    function: String = #function
  ) {
    log(
      message(),
      redacting: redactableMessage(),
      metadata: metadata(),
      backtraceOffset: backtraceOffset + 1,  // One more to account for the current call.
      file: file,
      line: line,
      function: function
    )
  }

  /// Log the message and optional metadata without specifying a function name.
  ///
  /// If specified, the `redacting` parameter will be appended after the primary message with a
  /// space in between.
  ///
  /// Note that the persistence of any information logged depends on the delegate. For example,
  /// metadata will only be persisted if the delegate supports it.
  ///
  /// The `file`, `line` and `function` are intended for internal use so they can capture the
  /// location of the call using the default parameter values. You shouldn't need to assign
  /// values to them. This works just as it does for standard Swift functions as in:
  /// https://developer.apple.com/documentation/swift/1539374-preconditionfailure
  /// Likewise, `backtraceOffset` is used internally to determine how far back to begin the
  /// back trace. You should not assign any value to it.
  ///
  /// - Parameters:
  ///   - messageGenerator: Closure which generates the message to log.
  ///   - redacting: Option message to append that will be redacted when persisted.
  ///   - metadata: Optional structured data to support reporting and investigation.
  ///   - backtraceOffset: Optional backtrace offset for fault logs.
  ///   - file: Don't specify as the default parameter is used internally.
  ///   - line: Don't specify as the default parameter is used internally.
  ///   - function: Don't specify as the default parameter is used internally.
  public func log(
    _ messageGenerator: @autoclosure () -> String,
    redacting redactableMessage: @autoclosure () -> String? = nil,
    metadata: @autoclosure () -> [String: LogMetaData]? = nil,
    backtraceOffset: UInt = 0,
    file: String = #file,
    line: Int = #line,
    function: String = #function
  ) {
    guard isLoggable else { return }
    guard let delegate = delegate else { return }

    let backTrace: [String]?
    if case .fault = level {
      // Total backtrace is one more to account for the current call.
      let totalBacktraceOffset = Int(backtraceOffset) + 1
      let symbols = Thread.callStackSymbols
      if symbols.count > totalBacktraceOffset + 1 {
        // Remove the current call since we don't want to include logging in the stack trace.
        backTrace = Array(symbols[totalBacktraceOffset...])
      } else {
        backTrace = nil
      }
    } else {
      backTrace = nil
    }

    let message = messageGenerator()
    let timestamp = Date()
    let record = LogRecord(
      logger: self,
      timestamp: timestamp,
      timezone: TimeZone.current,
      processId: ProcessInfo.processInfo.processIdentifier,
      processName: ProcessInfo.processInfo.processName,
      threadId: ThreadInfo.currentThreadNumber(),
      file: file,
      line: line,
      function: function,
      backTrace: backTrace,
      message: message,
      redactableMessage: redactableMessage(),
      metadata: metadata()
    )
    delegate.loggerDidRecordMessage(record)
    if prints {
      let formattedTimestamp = timestamp.encodeForLog(timezone: TimeZone.current)
      print("\(formattedTimestamp) \(message)")
    }
  }
}

// MARK: - Logger Modifiers

/// Extend `Logger` to support the modifier pattern.
///
/// A modifier returns a copy that matches the original logger except with a modified property. The
/// modifiers do not mutate the original logger.
@available(macOS 10.15, *)
extension Logger {
  /// Convenience modifier returning a copy using the `debug` logging level.
  public var debug: Logger { level(.debug) }

  /// Convenience modifier returning a copy using the `info` logging level.
  public var info: Logger { level(.info) }

  /// Convenience modifier returning a copy using the `error` logging level.
  public var error: Logger { level(.error) }

  /// Convenience modifier returning a copy using the `fault` logging level.
  public var fault: Logger { level(.fault) }

  /// Modifier returning a logger copy using the specified delegate.
  ///
  /// - Parameter delegate: The delegate to assign to the logger copy.
  /// - Returns: A copy of the logger with the specified delegate.
  func delegate(_ delegate: LoggerDelegate?) -> Logger {
    var logger = self
    logger.delegate = delegate
    return logger
  }

  /// Modifier returning a logger copy using the specified logging level.
  ///
  /// - Parameter level: The level to assign to the logger copy.
  /// - Returns: A copy of the logger with the specified level.
  public func level(_ level: Level) -> Logger {
    var logger = self
    logger.level = level
    return logger
  }

  /// Modifier returning a logger copy with the `prints` flag as specified.
  ///
  /// - Parameter shouldPrint: `true` for logs to also be printed to standard output.
  /// - Returns: A copy of the logger with the specified `prints` flag as specified.
  public func prints(_ shouldPrint: Bool) -> Logger {
    var logger = self
    logger.prints = shouldPrint
    return logger
  }
}

// MARK: - Logger Level

@available(macOS 10.15, *)
extension Logger {
  /// Logging level which maps to the corresponding Apple logging types as shown here:
  /// https://developer.apple.com/documentation/os/oslogtype
  ///
  /// Generally, the higher the logging level raw value, the more significant the log. More
  /// significant logs may have a longer persistence. Also, if a cutoff is specified, then
  /// lower level logs may not get persisted at all. Note that debug logs typically don't get
  /// persisted.
  public enum Level: Int, Encodable, Equatable, Comparable, Hashable {
    case debug, info, standard, error, fault

    /// Name of the current case (e.g. "debug" for debug).
    var name: String {
      String(describing: self)
    }

    /// Determine whether the left hand side is less than the right hand side.
    ///
    /// Comparable implementation is consistent with corresponding `rawValue` comparison. Higher
    /// levels correspond to higher significance.
    /// - Parameters:
    ///   - lhs: Level on the left hand side of the operator.
    ///   - rhs: Level on the right hand side of the operator.
    /// - Returns: `true` if the left hands side is less than the right hand side.
    public static func < (lhs: Logger.Level, rhs: Logger.Level) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}

// MARK: - Convenience

@available(macOS 10.15, *)
extension Logger {
  /// Creates a logger for the specified type.
  ///
  /// Initializer that infers the category from the specified type and the subsystem from the
  /// context in which it was called.
  ///
  /// The subsystem is the module which is derived from the context in which the initializer is
  /// called. The context defaults to `#fileID`
  /// (https://docs.swift.org/swift-book/ReferenceManual/Expressions.html). The specification notes
  /// that the module is the part of `#fileID` before the first "/".
  ///
  /// The type passed to the initializer will be used as the category with the textual category
  /// being the full type name excluding the module prefix. Since both the module and the type may
  /// generally contain components joined by periods, the module must first be extracted from the
  /// calling context and then removed from the fully qualified type name. If the module of the
  /// calling context doesn't match that of the type, then the category will be the simple type
  /// name. In the case of mangled names (e.g. private types) the mangled prefix will be stripped.
  ///
  /// - Parameters:
  ///   - type: Type for which the create the logger.
  ///   - context: Don't specify as the default parameter is used to infer the subsystem.
  public init(for type: Any.Type, context: String = #fileID) {
    // Module is the part of fileID before the first "/".
    let subsystem = String(context.prefix { $0 != "/" })
    self.subsystem = subsystem

    // Check whether the fully qualified category is prefixed by the subsystem. If not, just take
    // the category to be the fully qualified category.
    let typeName = String(reflecting: type)
    let subsystemPrefix = subsystem + "."

    guard typeName.hasPrefix(subsystemPrefix), typeName.endIndex != subsystemPrefix.endIndex else {
      // This would happen if the logger is instantiated outside of the type's module.
      self.category = String(describing: type)
      return
    }
    let baseTypeName = String(typeName.suffix(from: subsystemPrefix.endIndex))

    // Handle mangled type names which have a prefix in parentheses followed by a period.
    guard let lastParenIndex = baseTypeName.lastIndex(of: ")") else {
      // Type name isn't mangled, so we're done.
      self.category = baseTypeName
      return
    }

    // Prefix also includes the next "." so we need to shift by 2 to get to the name.
    let prefixIndex = baseTypeName.index(lastParenIndex, offsetBy: 2)
    guard prefixIndex != baseTypeName.endIndex else {
      // We shouldn't hit this, but just in case fallback to the simple type name.
      self.category = String(describing: type)
      return
    }
    self.category = String(baseTypeName.suffix(from: prefixIndex))
  }
}

// MARK: - Tracing

/// Support for fetching the thread number of the current thread.
@available(macOS 10.15, *)
private enum ThreadInfo {
  /// Thread safe regular expression for extracting the thread number.
  static private let regex: NSRegularExpression = {
    // The thread description is of the form: "<NSThread: 0x123456789>{number = 1, name = main}"
    try! NSRegularExpression(pattern: "number = (\\d+),")
  }()

  /// Get the thread number for the current thread.
  static func currentThreadNumber() -> Int {
    let threadDescription = Thread.current.description
    let match = regex.firstMatch(
      in: threadDescription,
      range: NSMakeRange(0, threadDescription.count)
    )
    // Extract capture group 1 from the match since it has the number we want.
    guard let groupRange = match?.range(at: 1) else { return -1 }
    let threadId = (threadDescription as NSString).substring(with: groupRange)
    return Int(threadId) ?? -1
  }
}
