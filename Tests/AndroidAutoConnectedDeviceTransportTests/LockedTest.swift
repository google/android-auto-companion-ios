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

@testable import AndroidAutoConnectedDeviceTransport

/// Unit tests for Locked.
class LockedTest: XCTestCase {
  @Locked private var lockedItem = 0
  private var lockMock = LockMock()

  override func setUp() {
    super.setUp()

    lockMock = LockMock()
    $lockedItem = Locked(wrappedValue: 0, lock: lockMock)
  }

  public func testInitialValue() {
    let testValue = 31
    $lockedItem = Locked(wrappedValue: testValue)

    XCTAssertEqual(lockedItem, testValue)
  }

  public func testAssignedValue() {
    let testValue = 53
    lockedItem = testValue

    XCTAssertEqual(lockedItem, testValue)
  }

  public func testGetValue_LockUnlockCalled() {
    let _ = lockedItem + 1

    XCTAssertTrue(lockMock.lockCalled)
    XCTAssertTrue(lockMock.unlockCalled)
  }

  public func testSetValue_LockUnlockCalled() {
    lockedItem = 1

    XCTAssertTrue(lockMock.lockCalled)
    XCTAssertTrue(lockMock.unlockCalled)
  }
}

/// Mock for a lock.
private class LockMock: NSLocking {
  var lockCalled = false
  var unlockCalled = false

  func lock() {
    lockCalled = true
  }

  func unlock() {
    unlockCalled = true
  }
}
