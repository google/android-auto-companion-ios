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

/// Property wrapper for locking read/write access to the underlying value.
///
/// Note that if desired, a single lock may be shared among several properties.
@propertyWrapper
struct Locked<T> {
  /// Lock which synchronizes access to the raw value.
  let lock: NSLocking

  /// Underlying value whose access is synchronized by the lock.
  var rawValue: T

  /// Access to the raw value synchronized by the lock.
  var wrappedValue: T {
    get {
      lock.lock()
      defer { lock.unlock() }
      return rawValue
    }

    set {
      lock.lock()
      defer { lock.unlock() }
      rawValue = newValue
    }
  }

  /// Access the property wrapper itself for reassignment of the wrapper.
  var projectedValue: Self {
    get { self }
    set { self = newValue }
  }

  /// Initializer specifying the raw value and the lock.
  ///
  /// - Parameters:
  ///   - wrappedValue: Raw value to which access is locked.
  ///   - lock: The lock which locks access to the wrapped value.
  init(wrappedValue: T, lock: NSLocking = NSLock()) {
    self.rawValue = wrappedValue
    self.lock = lock
  }
}
