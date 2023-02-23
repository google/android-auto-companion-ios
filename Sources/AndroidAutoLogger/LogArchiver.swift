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

/// Archive logs to persistent storage.
@available(macOS 10.15, *)
public actor LogArchiver: LoggerDelegate {
  /// Log for reporting logging errors.
  static private let log = OSLog(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "LogArchiver"
  )

  /// Maximum number of records that can pile up before we begin pruning.
  static private let backlogLimit = 50

  /// Number of records to drop when clearing the backlog.
  static private let backlogDropCount = backlogLimit / 2

  /// Delay (nanoseconds) from when the write is dispatched and when it can begin executing.
  ///
  /// Allow enough time to write a batch of records together but not so much time that it would
  /// risk information loss.
  static private let batchWriteDelayNanoseconds: UInt64 = 1_000_000_000

  /// Directory for the log files that are actively being written.
  static public var logDirectory: String { LogSerialWriter.logDirectory }

  /// Records to be persisted.
  private var records: [LogRecord] = []

  /// Serially writes records to the persistent store.
  private var serialWriter: LogSerialWriter

  /// Initialize with `FileLogStoreFactory` for persistence.
  init() {
    self.init(persistentStoreFactory: FileLogStoreFactory())
  }

  /// Initialize using the specified persistence.
  ///
  /// - Parameter persistentStoreFactory: Factory to use for persistence.
  init(persistentStoreFactory: PersistentLogStoreFactory) {
    serialWriter = LogSerialWriter(persistentStoreFactory: persistentStoreFactory)
  }

  /// Get the existing URLs for the logs.
  nonisolated public func getLogURLs() -> [URL] {
    let fileManager = FileManager.default

    let directory = Self.logDirectory
    guard fileManager.fileExists(atPath: directory) else {
      os_log("The log files directory is missing.", log: Self.log)
      return []
    }

    guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else { return [] }

    var urls: [URL] = []
    for fileName in files {
      let path = NSString.path(withComponents: [directory, fileName])
      let url = URL(fileURLWithPath: path)
      urls.append(url)
    }

    return urls
  }

  /// Log the record to an archive file.
  ///
  /// Redacted messages will not be included.
  ///
  /// - Parameter record: The record to log.
  nonisolated public func loggerDidRecordMessage(_ record: LogRecord) {
    // Unless the `DEBUG` flag is set, only archive messages with level greater than debug.
    // If the `DEBUG` flag is set, ignore the level and schedule all messages to be archived.
    #if !DEBUG
      // Only persist records with level greater than debug.
      guard record.level > .debug else { return }
    #endif

    Task {
      await archive(record)
    }
  }

  /// Archive the record to the persistent store.
  private func archive(_ record: LogRecord) {
    pruneRecordsIfNeeded()
    records.append(record)

    // Exactly one record means the buffer has been flushed, so we need to schedule new writes.
    guard records.count == 1 else { return }

    // Schedule persistent writes after a short delay to allow for batching.
    Task.detached(priority: .utility) {
      do {
        try await Task.sleep(nanoseconds: Self.batchWriteDelayNanoseconds)
      } catch {
        // Failure should only be for canceling this task which shouldn't happen.
        assertionFailure("Unexpected error waiting on sleep: \(error)")
      }
      await self.persistRecords()
    }
  }

  /// Prune the records if the count exceeds the batch limit.
  ///
  /// When the record count exceeds the backlog limit, records are pruned starting at the lowest
  /// level and continuing with successively higher levels until the count falls below the limit.
  private func pruneRecordsIfNeeded() {
    guard records.count > Self.backlogLimit else { return }

    pruneRecords(below: .standard)
    if records.count > Self.backlogLimit {
      pruneRecords(below: .error)
    }
    if records.count > Self.backlogLimit {
      records = Array(records.dropFirst(Self.backlogDropCount))
    }
  }

  /// Prune the records that are below the specified level.
  ///
  /// Calling this method from a thread other than from the owner of the lock will assert.
  ///
  /// - Parameter level: The level below which records will be pruned.
  private func pruneRecords(below level: Logger.Level) {
    records = records.filter { $0.level >= level }
  }

  private func nextRecordsToPersist() -> [LogRecord] {
    let batchRecords = records
    records = []
    return batchRecords
  }

  /// Persist all of the records and clear them from the buffer.
  nonisolated private func persistRecords() async {
    let batchRecords = await nextRecordsToPersist()

    guard batchRecords.count > 0 else { return }

    do {
      try await serialWriter.write(batchRecords)
    } catch {
      os_log(
        "Error writing records: %s",
        log: Self.log,
        type: .error,
        error.localizedDescription
      )
    }
  }
}

/// Serializes the writing of log records to the perisistent store.
private actor LogSerialWriter {
  /// Factory for making the persistent store.
  private let persistentStoreFactory: PersistentLogStoreFactory

  /// Directory for the log files that are actively being written.
  static var logDirectory: String {
    #if os(iOS) || os(watchOS)
      return NSString.path(withComponents: [
        NSHomeDirectory(), "Documents", "Logs",
      ])
    #elseif os(macOS)
      return NSString.path(withComponents: [
        NSHomeDirectory(), "Library", "Logs", ProcessInfo.processInfo.processName,
      ])
    #else
      #error("Unsupported OS for logDirectory.")
    #endif
  }

  /// Initialize using the specified persistence.
  ///
  /// - Parameter persistentStoreFactory: Factory to use for persistence.
  init(persistentStoreFactory: PersistentLogStoreFactory) {
    self.persistentStoreFactory = persistentStoreFactory
  }

  /// Serially write the specified batch of records.
  ///
  /// - Parameter records: The batch records to write to the persistent storage.
  /// - Throws: An error if the persistent log store cannot be created.
  func write(_ records: [LogRecord]) throws {
    var store = try persistentStoreFactory.makeStore(
      directory: Self.logDirectory, date: Date(), carName: nil)

    for record in records {
      if !store.canLogDate(record.timestamp) {
        store = try persistentStoreFactory.makeStore(
          directory: Self.logDirectory,
          date: record.timestamp,
          carName: nil
        )
      }
      // If a single record fails to write just drop that one record and keep going as this might
      // be an error specific to this record (e.g. encoding).
      try? store.writeRecord(record)
    }
  }
}
