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

/// Monitor conformance for certain peripheral activities (e.g. association, connection).
///
/// If we were targeting iOS 13+, we would instead use Combine. For now, we need a common way to
/// handle event monitors. See https://developer.apple.com/documentation/combine for details.
public protocol PeripheralActivityMonitor {
  /// Cancel the monitor.
  func cancel()
}
