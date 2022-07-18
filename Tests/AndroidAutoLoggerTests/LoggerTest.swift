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

import XCTest

@testable import AndroidAutoLogger

/// Unit tests for Logger.
class LoggerTest: XCTestCase {
  var log = Logger(subsystem: "TestSystem", category: "TestCat")
  fileprivate let delegateMock = LoggerDelegateMock()

  override func setUp() {
    super.setUp()

    log.delegate = delegateMock
  }

  override func tearDown() {
    super.tearDown()

    log.delegate = nil
  }

  /// Tests that the expected category is created given the mangled type name (for private types).
  public func testInferredCategoryForPrivateType() {
    let log = Logger(for: PrivateSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Expect that type name should be mangled.
    let typeName = String(reflecting: PrivateSampleTarget.self)
    XCTAssertNotEqual("\(moduleName).PrivateSampleTarget", typeName)
    XCTAssertTrue(typeName.contains(")"))

    XCTAssertEqual(log.subsystem, moduleName)
    XCTAssertEqual(log.category, "PrivateSampleTarget")
  }

  /// Tests that the expected category is created given the unmangled type names.
  public func testInferredCategoryForInternalType() {
    let log = Logger(for: InternalSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Expect that type name shouldn't be mangled.
    let typeName = String(reflecting: InternalSampleTarget.self)
    XCTAssertEqual("\(moduleName).InternalSampleTarget", typeName)
    XCTAssertFalse(typeName.contains(")"))

    XCTAssertEqual(log.subsystem, moduleName)
    XCTAssertEqual(log.category, "InternalSampleTarget")
  }

  public func testLoggerLogsRecord() {
    let line = #line + 1  // This line must be kept right before the log() call line.
    log("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.subsystem, "TestSystem")
    XCTAssertEqual(record.category, "TestCat")
    XCTAssertEqual(record.level, .standard)
    XCTAssertEqual(record.message, "Test")
    XCTAssertNil(record.metadata)
    XCTAssertNil(record.redactableMessage)
    XCTAssertEqual(record.file, #file)
    XCTAssertEqual(record.function, #function)
    XCTAssertEqual(record.line, line)

    // Since the test is run on the main thread, we should be on thread number 1.
    XCTAssertEqual(record.threadId, 1)
  }

  // Test calling the log as a function.
  public func testLoggerCallLogsRecord() {
    let line = #line + 1  // This line must be kept right before the log() call line.
    log("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.subsystem, "TestSystem")
    XCTAssertEqual(record.category, "TestCat")
    XCTAssertEqual(record.level, .standard)
    XCTAssertEqual(record.message, "Test")
    XCTAssertNil(record.redactableMessage)
    XCTAssertNil(record.metadata)
    XCTAssertEqual(record.file, #file)
    XCTAssertEqual(record.function, #function)
    XCTAssertEqual(record.line, line)

    // Since the test is run on the main thread, we should be on thread number 1.
    XCTAssertEqual(record.threadId, 1)
  }


  public func testLoggerRedaction() {
    log("Test", redacting: "abc123")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    // Test redaction.
    XCTAssertNotNil(record.redactableMessage)
    XCTAssertEqual(record.redactableMessage, "abc123")
  }

  public func testLoggerLevelModifiers() {
    // Test modifier methods.
    XCTAssertEqual(log.level(.debug).level, Logger.Level.debug)
    XCTAssertEqual(log.level(.info).level, Logger.Level.info)
    XCTAssertEqual(log.level(.standard).level, Logger.Level.standard)
    XCTAssertEqual(log.level(.error).level, Logger.Level.error)
    XCTAssertEqual(log.level(.fault).level, Logger.Level.fault)

    // Test convenience modifier computed properties.
    XCTAssertEqual(log.debug.level, Logger.Level.debug)
    XCTAssertEqual(log.info.level, Logger.Level.info)
    XCTAssertEqual(log.error.level, Logger.Level.error)
    XCTAssertEqual(log.fault.level, Logger.Level.fault)
  }

  public func testLoggerDebugLogRecord() {
    log.debug("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .debug)
  }

  public func testLoggerInfoLogRecord() {
    log.info("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .info)
  }

  public func testLoggerErrorLogRecord() {
    log.error("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .error)
  }

  public func testLoggerFaultLogRecord() {
    let backTrace = Thread.callStackSymbols
    log.fault("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .fault)

    // Verify that the backtrace is not nil and the length matches.
    // Note the stack symbol prefixes will not match since the stack trace was captured in the
    // log call with the first symbol stripped to exclude the log in the backtrace.
    XCTAssertNotNil(record.backTrace)
    XCTAssertEqual(backTrace.count, record.backTrace?.count ?? 0)
  }

  public func testLoggerCallFaultLogRecord() {
    let backTrace = Thread.callStackSymbols

    log.fault("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .fault)

    // Verify that the backtrace is not nil and the length matches.
    // Note the stack symbol prefixes will not match since the stack trace was captured in the
    // log call with the first symbol stripped to exclude the log in the backtrace.
    XCTAssertNotNil(record.backTrace)
    XCTAssertEqual(backTrace.count, record.backTrace?.count ?? 0)
  }
}

/// Mock for the Logger delegate.
private class LoggerDelegateMock: LoggerDelegate {
  var lastRecord: LogRecord? = nil

  func loggerDidRecordMessage(_ record: LogRecord) {
    lastRecord = record
  }
}

/// Private type for which we can test Logger category inference.
private enum PrivateSampleTarget {}

/// Internal type for which we can test Logger category inference.
enum InternalSampleTarget {}
