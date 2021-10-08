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

/// Abstraction of the state of a transport's radio.
public protocol RadioState: CustomStringConvertible {
  /// Indicates whether the radio is powered on.
  var isPoweredOn: Bool { get }

  /// Indicates whether the radio is powered off.
  var isPoweredOff: Bool { get }

  /// Indicates whether the radio is in an unknown state.
  var isUnknown: Bool { get }

  /// Indicates whether the radio is in another custom state.
  var isOther: Bool { get }
}
