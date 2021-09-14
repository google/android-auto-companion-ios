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
@available(iOS 10.0, *)
public class LogArchiver: LoggerDelegate {
  /// Log for reporting logging errors.
  static private let log = OSLog(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "LogArchiver"
  )

  /// Maximum number of records that can pile up before we begin pruning.
  static private let backlogLimit = 50

  /// Number of records to drop when clearing the backlog.
  static private let backlogDropCount = backlogLimit / 2

  /// Delay (seconds) from when the write is dispatched and when it can begin executing.
  ///
  /// Allow enough time to write a batch of records together but not so much time that it would
  /// risk information loss.
  static private let batchWriteDelay = DispatchTimeInterval.seconds(1)

  /// Directory for the log files that are actively being written.
  static public var logDirectory: String {
    #if os(iOS) || os(watchOS)
    return NSString.path(withComponents: [
      NSHomeDirectory(), "Documents", "Logs",
    ])
    #elseif os(macOS)
    return NSString.path(withComponents: [
      NSHomeDirectory(), "Library", "Logs", ProcessInfo.processInfo.processName
    ])
    #else
    #error("Unsupported OS for logDirectory.")
    #endif
  }

  /// Factory for making the persistent store.
  private let persistentStoreFactory: PersistentLogStoreFactory

  /// Low priority queue on which the records are persisted.
  private let queue = DispatchQueue(label: "LogArchiver", qos: .utility)

  /// Lock which allows for safe access from multiple threads.
  private var lock = os_unfair_lock()

  /// Records to be persisted.
  ///
  /// Note that `lock` needs to be held for safe access to the records.
  private var records_locked: [LogRecord] = []

  /// Initialize with `FileLogStoreFactory` for persistence.
  convenience init() {
    self.init(persistentStoreFactory: FileLogStoreFactory())
  }

  /// Initialize using the specified persistence.
  ///
  /// - Parameter persistentStoreFactory: Factory to use for persistence.
  init(persistentStoreFactory: PersistentLogStoreFactory) {
    self.persistentStoreFactory = persistentStoreFactory
  }

  /// Get the existing URLs for the logs.
  public func getLogURLs() -> [URL] {
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
  public func loggerDidRecordMessage(_ record: LogRecord) {
    os_unfair_lock_assert_not_owner(&lock)

    // Only persist records with level greater than debug.
    guard record.level > .debug else { return }

    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }

    pruneRecordsIfNeeded_locked()
    records_locked.append(record)
    // Exactly one record means the buffer has been flushed, so we need to queue new writes.
    if records_locked.count == 1 {
      queue.asyncAfter(deadline: .now() + Self.batchWriteDelay) {
        self.persistRecords_onQueue()
      }
    }
  }

  /// Prune the records if the count exceeds the batch limit.
  ///
  /// When the record count exceeds the backlog limit, records are pruned starting at the lowest
  /// level and continuing with successively higher levels until the count falls below the limit.
  ///
  /// Calling this method from a thread other than from the owner of the lock will assert.
  private func pruneRecordsIfNeeded_locked() {
    os_unfair_lock_assert_owner(&lock)

    guard records_locked.count > Self.backlogLimit else { return }

    pruneRecords_locked(below: .standard)
    if records_locked.count > Self.backlogLimit {
      pruneRecords_locked(below: .error)
    }
    if records_locked.count > Self.backlogLimit {
      records_locked = Array(records_locked.dropFirst(Self.backlogDropCount))
    }
  }

  /// Prune the records that are below the specified level.
  ///
  /// Calling this method from a thread other than from the owner of the lock will assert.
  ///
  /// - Parameter level: The level below which records will be pruned.
  private func pruneRecords_locked(below level: Logger.Level) {
    os_unfair_lock_assert_owner(&lock)

    records_locked = records_locked.filter { $0.level >= level }
  }

  /// Persist all of the records and clear them from the buffer.
  ///
  /// Calling this method from a queue other than `queue` will assert.
  private func persistRecords_onQueue() {
    dispatchPrecondition(condition: .onQueue(queue))
    os_unfair_lock_assert_not_owner(&lock)

    os_unfair_lock_lock(&lock)
    let batchRecords = records_locked
    records_locked = []
    os_unfair_lock_unlock(&lock)

    guard batchRecords.count > 0 else { return }

    do {
      try writeRecords_onQueue(batchRecords)
    } catch {
      os_log(
        "Error writing records: %s",
        log: Self.log,
        type: .error,
        error.localizedDescription
      )
    }
  }

  /// Write the specified batch of records.
  ///
  /// Calling this method from a queue other than `queue` will assert.
  ///
  /// - Parameter records: The batch records to write to the persistent storage.
  /// - Throws: An error if the persistent log store cannot be created.
  private func writeRecords_onQueue(_ records: [LogRecord]) throws {
    dispatchPrecondition(condition: .onQueue(queue))

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
