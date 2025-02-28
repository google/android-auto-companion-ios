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

internal import Foundation
internal import Testing

@testable internal import AndroidAutoLogger

/// Unit tests for Logger.
struct LoggerTests {
  private let log: Logger
  private let delegateMock = LoggerDelegateMock()

  init() {
    var log = Logger(subsystem: "TestSystem", category: "TestCat")
    log.delegate = delegateMock
    self.log = log
  }

  /// Tests that the expected category is created given the mangled type name (for private types).
  @Test("Infers category from mangled type name")
  func infersCategoryFromMangledTypeName() throws {
    let log = Logger(for: PrivateSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Require that type name is mangled.
    let typeName = String(reflecting: PrivateSampleTarget.self)
    try #require("\(moduleName).PrivateSampleTarget" != typeName)
    try #require(typeName.contains(")"))

    // Expect the subsystem to be the module name and the category the simple type name.
    #expect(log.subsystem == moduleName)
    #expect(log.category == "PrivateSampleTarget")
  }

  /// Tests that the expected category is created given the unmangled type names.
  @Test("Infers category from unmangled type name")
  func infersCategoryFromUnmangledTypeName() throws {
    let log = Logger(for: InternalSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Require that type name isn't mangled.
    let typeName = String(reflecting: InternalSampleTarget.self)
    try #require("\(moduleName).InternalSampleTarget" == typeName)
    try #require(!typeName.contains(")"))

    #expect(log.subsystem == moduleName)
    #expect(log.category == "InternalSampleTarget")
  }

  @Test("Logger logs record")
  @MainActor func loggerLogsRecord() throws {
    let line = #line + 1  // This line must be kept right before the log() call line.
    log.log("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.subsystem == "TestSystem")
    #expect(record.category == "TestCat")
    #expect(record.level == .standard)
    #expect(record.message == "Test")
    #expect(record.metadata == nil)
    #expect(record.redactableMessage == nil)
    #expect(record.file == #file)
    #expect(record.function == #function)
    #expect(record.line == line)

    // Since the test is run on the main thread, we should be on thread number 1.
    #expect(record.threadId == 1)
  }

  @Test("Calling logger as a function logs record")
  @MainActor func callingLoggerLogsRecord() throws {
    let line = #line + 1  // This line must be kept right before the log() call line.
    log("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.subsystem == "TestSystem")
    #expect(record.category == "TestCat")
    #expect(record.level == .standard)
    #expect(record.message == "Test")
    #expect(record.metadata == nil)
    #expect(record.redactableMessage == nil)
    #expect(record.file == #file)
    #expect(record.function == #function)
    #expect(record.line == line)

    // Since the test is run on the main thread, we should be on thread number 1.
    #expect(record.threadId == 1)
  }

  @Test("Logger redacts message")
  func loggerRedactsMessage() throws {
    log("Test", redacting: "abc123")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    // Test redaction.
    #expect(record.redactableMessage == "abc123")
  }

  @Test(
    "Logger level matches level modifier",
    arguments: [Logger.Level.debug, .info, .standard, .error, .fault]
  )
  func loggerLevelMatchesLevelModifier(level: Logger.Level) {
    // Test modifier methods.
    #expect(log.level(level).level == level)
  }

  @Test("Logger convience modifier matches level")
  func loggerLevelMatchesConvenienceLevelModifier() {
    #expect(log.debug.level == Logger.Level.debug)
    #expect(log.info.level == Logger.Level.info)
    #expect(log.error.level == Logger.Level.error)
    #expect(log.fault.level == Logger.Level.fault)
  }

  @Test("Debug logger logs debug record")
  func debugLoggerLogsDebugRecord() throws {
    log.debug("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.level == .debug)
  }

  @Test("Info logger logs info record")
  func infoLoggerLogsInfoRecord() throws {
    log.info("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.level == .info)
  }

  @Test("Error logger logs error record")
  func errorLoggerLogsErroRecord() throws {
    log.error("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.level == .error)
  }

  @Test("Fault logger logs fault record")
  func faultLoggerLogsFaultRecord() throws {
    let backTrace = Thread.callStackSymbols
    log.fault("Test")

    #expect(delegateMock.lastRecord != nil)
    let record = try #require(delegateMock.lastRecord)

    #expect(record.level == .fault)

    // Verify that the backtrace is not nil and the length matches.
    // Note the stack symbol prefixes will not match since the stack trace was captured in the
    // log call with the first symbol stripped to exclude the log in the backtrace.
    #expect(record.backTrace != nil)
    let recordBackTrace = try #require(record.backTrace)
    #expect(backTrace.count == recordBackTrace.count)
  }
}

/// Mock for the Logger delegate.
private final class LoggerDelegateMock: LoggerDelegate, @unchecked Sendable {
  var lastRecord: LogRecord? = nil

  func loggerDidRecordMessage(_ record: LogRecord) {
    lastRecord = record
  }
}

/// Private type for which we can test Logger category inference.
private enum PrivateSampleTarget {}

/// Internal type for which we can test Logger category inference.
enum InternalSampleTarget {}
