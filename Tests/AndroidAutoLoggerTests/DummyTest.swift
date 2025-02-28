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

internal import XCTest

// TODO: b/349867353 Remove this test once Swift Tests are supported in infrastructure testing.

/// Swift Testing isn't yet fully supported by the testing infrastructure, so we need at least one `XCTest` test to prevent it failing.
class DummyTest: XCTestCase {
  /// We need at least one  test and here it is.
  func testAnything() {}
}
