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

/// Protocol for persisting log records to storage.
@available(macOS 10.15, *)
public protocol PersistentLogStore {
  /// Returns `true` if the specified date represents the same day as this archive's date in GMT.
  ///
  /// - Parameter date: The date with which to compare.
  func canLogDate(_ date: Date) -> Bool

  /// Write the specified record to the log file.
  ///
  /// - Parameter record: The log record to append.
  /// - Throws: An error if the record cannot be written.
  func writeRecord(_ record: LogRecord) throws

  /// Append the data to the log file.
  ///
  /// - Parameter data: The data to append.
  func appendData(_ data: Data)
}

/// Manage the persistent storage of the log files.
///
/// The log file format is in JSON with each record being an element of the array.
@available(macOS 10.15, *)
public class FileLogStore: PersistentLogStore {
  /// Duration (seconds) to retain the log files.
  static private let logRetentionDuration: TimeInterval = 7 * 24 * 3_600

  /// File header which is the opening bracket of the array and a newline for separation.
  static private let fileHeader = Data("[\n".utf8)

  /// File footer which is the closing bracket of the array and a newline for separation.
  static private let fileFooter = Data("\n]".utf8)

  /// Comma delimiter (including newlines) to separate records.
  static private let recordSeparator = Data("\n,\n".utf8)

  /// Formatter for the date part of the log filenames.
  ///
  /// Use a fixed time zone at GMT so our file names are predictable. We don't want the file names
  /// changing when the user moves between time zones.
  ///
  /// Note that DateFormatter is thread safe on iOS 7+.
  /// See: https://developer.apple.com/documentation/foundation/dateformatter
  static private let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-'GMT'"
    formatter.timeZone = TimeZone.init(secondsFromGMT: 0)
    return formatter
  }()

  /// Each log file corresponds to a unique day in GMT.
  private let date: Date

  /// Directory in which to write the logs.
  private let logDirectory: String

  /// File handle to the log file being written.
  private var fileHandle: FileHandle? = nil

  /// Initialize `FileLogStore`.
  ///
  /// - Parameters:
  ///   - directory: The Directory in which to write the logs.
  ///   - date: The time to write the log.
  ///   - carName: The name of the car that the logs are for.
  init(directory: String, date: Date, carName: String? = nil) throws {
    self.logDirectory = directory
    self.date = date

    let filePath = logFilePath(for: date, carName: carName)
    let fileManager = FileManager.default
    if !fileManager.fileExists(atPath: filePath) {
      pruneLogFiles()

      let _ = try fileManager.createDirectory(
        atPath: logDirectory,
        withIntermediateDirectories: true,
        attributes: nil
      )
      let success = fileManager.createFile(atPath: filePath, contents: nil, attributes: nil)
      guard success else {
        throw StoreError.fileCreationFailure(filePath)
      }
    }
    fileHandle = FileHandle(forWritingAtPath: filePath)

    guard let fileHandle = fileHandle else {
      throw StoreError.noFileHandle(filePath)
    }
    fileHandle.seekToEndOfFile()
  }

  deinit {
    fileHandle?.closeFile()
  }

  /// Returns `true` if a record with the specified date can be logged using this store.
  ///
  /// Records are partitioned by timestamp to be written to a log file which is named according to
  /// its date. So, the date label for the file name is compared to determine whether the store can
  /// log a record with the specified date.
  ///
  /// For consistency across potentially changing time zones, we use a fixed time zone when
  /// comparing dates.
  ///
  /// - Parameter date: The date for which to check.
  public func canLogDate(_ date: Date) -> Bool {
    fileNameDateLabel(self.date) == fileNameDateLabel(date)
  }

  /// Write the specified record to the log file.
  ///
  /// - Parameter record: The log record to append.
  /// - Throws: An error if the record cannot be written.
  public func writeRecord(_ record: LogRecord) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let recordData = try encoder.encode(record)
    appendData(recordData)
  }

  /// Append the data to the log file.
  ///
  /// - Parameter data: The data to append.
  public func appendData(_ data: Data) {
    guard let fileHandle = fileHandle else { return }

    var output = Data()
    if fileHandle.offsetInFile == 0 {
      // Empty file -> append the file header.
      output.append(Self.fileHeader)
    } else {
      // Existing records -> overwrite the file footer with the record separator.
      fileHandle.seek(toFileOffset: fileHandle.offsetInFile - UInt64(Self.fileFooter.count))
      output.append(Self.recordSeparator)
    }
    output.append(data)
    output.append(Self.fileFooter)
    fileHandle.write(output)
  }

  /// Generate the part of the filename that is based on the date.
  private func fileNameDateLabel(_ date: Date) -> String {
    Self.dateFormatter.string(from: date)
  }

  /// File name for the specified date and car name.
  private func logFileName(for date: Date, carName: String? = nil) -> String {
    let dateLabel = fileNameDateLabel(date)
    if let carName = carName {
      return "Log-\(carName)-\(dateLabel).aalog"
    }
    return "Log-\(dateLabel).aalog"
  }

  /// File path for the specified date and name.
  private func logFilePath(for date: Date, carName: String? = nil) -> String {
    let fileName = logFileName(for: date, carName: carName)
    return NSString.path(withComponents: [logDirectory, fileName])
  }

  /// Prune the log files that are older than the retention duration.
  private func pruneLogFiles() {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: logDirectory) else { return }

    let retentionDate = Date(timeIntervalSinceNow: -Self.logRetentionDuration)
    guard let files = try? fileManager.contentsOfDirectory(atPath: logDirectory) else { return }

    for fileName in files {
      let filePath = NSString.path(withComponents: [logDirectory, fileName])
      guard fileManager.isDeletableFile(atPath: filePath) else { continue }
      try? pruneLogFileIfNeeded(filePath: filePath, retentionDate: retentionDate)
    }
  }

  /// Prune the log file if it's older than the retention date.
  private func pruneLogFileIfNeeded(filePath: String, retentionDate: Date) throws {
    let fileManager = FileManager.default
    let attributes = try fileManager.attributesOfItem(atPath: filePath)
    guard let creationDate = attributes[.creationDate] as? Date else { return }
    if creationDate < retentionDate {
      try fileManager.removeItem(atPath: filePath)
    }
  }
}

// MARK: - StoreError extension

@available(macOS 10.15, *)
extension FileLogStore {
  /// Storage errors.
  enum StoreError: Error {
    case fileCreationFailure(String)
    case noFileHandle(String)
  }
}
