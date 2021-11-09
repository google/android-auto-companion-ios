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
@available(iOS 10.0, *)
class LoggerTest: XCTestCase {
  var logger = Logger(subsystem: "TestSystem", category: "TestCat")
  fileprivate let delegateMock = LoggerDelegateMock()

  override func setUp() {
    super.setUp()

    logger.delegate = delegateMock
  }

  override func tearDown() {
    super.tearDown()

    logger.delegate = nil
  }

  /// Tests that the expected category is created given the mangled type name (for private types).
  public func testInferredCategoryForPrivateType() {
    let logger = Logger(for: PrivateSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Expect that type name should be mangled.
    let typeName = String(reflecting: PrivateSampleTarget.self)
    XCTAssertNotEqual("\(moduleName).PrivateSampleTarget", typeName)
    XCTAssertTrue(typeName.contains(")"))

    XCTAssertEqual(logger.subsystem, moduleName)
    XCTAssertEqual(logger.category, "PrivateSampleTarget")
  }

  /// Tests that the expected category is created given the unmangled type names.
  public func testInferredCategoryForInternalType() {
    let logger = Logger(for: InternalSampleTarget.self)

    let moduleName = "third_party_swift_AndroidAutoCompanion_LoggerTestsLib"

    // Expect that type name shouldn't be mangled.
    let typeName = String(reflecting: InternalSampleTarget.self)
    XCTAssertEqual("\(moduleName).InternalSampleTarget", typeName)
    XCTAssertFalse(typeName.contains(")"))

    XCTAssertEqual(logger.subsystem, moduleName)
    XCTAssertEqual(logger.category, "InternalSampleTarget")
  }

  public func testLoggerLogsRecord() {
    let line = #line + 1  // This line must be kept right before the logger.log() call line.
    logger.log("Test")

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

  // Test calling the logger as a function.
  #if swift(>=5.2)
    public func testLoggerCallLogsRecord() {
      let line = #line + 1  // This line must be kept right before the logger() call line.
      logger("Test")

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
  #endif

  public func testLoggerRedaction() {
    logger("Test", redacting: "abc123")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    // Test redaction.
    XCTAssertNotNil(record.redactableMessage)
    XCTAssertEqual(record.redactableMessage, "abc123")
  }

  public func testLoggerLevelModifiers() {
    // Test modifier methods.
    XCTAssertEqual(logger.level(.debug).level, Logger.Level.debug)
    XCTAssertEqual(logger.level(.info).level, Logger.Level.info)
    XCTAssertEqual(logger.level(.standard).level, Logger.Level.standard)
    XCTAssertEqual(logger.level(.error).level, Logger.Level.error)
    XCTAssertEqual(logger.level(.fault).level, Logger.Level.fault)

    // Test convenience modifier computed properties.
    XCTAssertEqual(logger.debug.level, Logger.Level.debug)
    XCTAssertEqual(logger.info.level, Logger.Level.info)
    XCTAssertEqual(logger.error.level, Logger.Level.error)
    XCTAssertEqual(logger.fault.level, Logger.Level.fault)
  }

  public func testLoggerDebugLogRecord() {
    logger.debug.log("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .debug)
  }

  public func testLoggerInfoLogRecord() {
    logger.info.log("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .info)
  }

  public func testLoggerErrorLogRecord() {
    logger.error.log("Test")

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .error)
  }

  public func testLoggerFaultLogRecord() {
    let backTrace = Thread.callStackSymbols

    #if swift(>=5.2)
      logger.fault("Test")
    #else
      logger.fault.log("Test")
    #endif

    XCTAssertNotNil(delegateMock.lastRecord)
    guard let record = delegateMock.lastRecord else { return }

    XCTAssertEqual(record.level, .fault)

    // Verify that the backtrace is not nil and the length matches.
    // Note the stack symbol prefixes will not match since the stack trace was captured in the
    // logger call with the first symbol stripped to exclude the log in the backtrace.
    XCTAssertNotNil(record.backTrace)
    XCTAssertEqual(backTrace.count, record.backTrace?.count ?? 0)
  }

  #if swift(>=5.2)
    public func testLoggerCallFaultLogRecord() {
      let backTrace = Thread.callStackSymbols

      logger.fault("Test")

      XCTAssertNotNil(delegateMock.lastRecord)
      guard let record = delegateMock.lastRecord else { return }

      XCTAssertEqual(record.level, .fault)

      // Verify that the backtrace is not nil and the length matches.
      // Note the stack symbol prefixes will not match since the stack trace was captured in the
      // logger call with the first symbol stripped to exclude the log in the backtrace.
      XCTAssertNotNil(record.backTrace)
      XCTAssertEqual(backTrace.count, record.backTrace?.count ?? 0)
    }
  #endif
}

/// Mock for the Logger delegate.
@available(iOS 10.0, *)
private class LoggerDelegateMock: LoggerDelegate {
  var lastRecord: LogRecord? = nil

  func loggerDidRecordMessage(_ record: LogRecord) {
    lastRecord = record
  }
}

/// Private type for which we can test Logger category inference.
@available(iOS 10.0, *)
private enum PrivateSampleTarget {}

/// Internal type for which we can test Logger category inference.
@available(iOS 10.0, *)
enum InternalSampleTarget {}
