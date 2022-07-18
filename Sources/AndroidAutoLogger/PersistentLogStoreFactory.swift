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

/// Protocol for factories which make log stores.
@available(macOS 10.15, *)
public protocol PersistentLogStoreFactory {
  /// Make storage for logs with the specified date.
  ///
  /// Note that the date for the logs is based on GMT providing a consistent file timestamp
  /// independent of the user's time zone which might change while logging.
  ///
  /// - Parameters:
  ///   - directory: Directory within which to write logs.
  ///   - date: Date for which to record the logs.
  ///   - name: Name of the car that logs are for.
  /// - Returns: The log store.
  /// - Throws: If the storage cannot be instantiated.
  func makeStore(directory: String, date: Date, carName: String?) throws -> PersistentLogStore
}

/// Factory which persists the logs to a file.
@available(macOS 10.15, *)
public struct FileLogStoreFactory: PersistentLogStoreFactory {
  /// Creates a new instance of this factory.
  public init() {}

  /// Make storage for logs with the specified date.
  ///
  /// Note that the date for the logs is based on GMT providing a consistent file timestamp
  /// independent of the user's time zone which might change while logging.
  ///
  /// - Parameters:
  ///   - directory: Directory within which to write logs.
  ///   - date: Date for which to record the logs.
  ///   - name: Name of the car that logs are for.
  /// - Returns: The log store.
  /// - Throws: If the storage cannot be instantiated.
  public func makeStore(directory: String, date: Date, carName: String?) throws
    -> PersistentLogStore
  {
    try FileLogStore(directory: directory, date: date, carName: carName)
  }
}
