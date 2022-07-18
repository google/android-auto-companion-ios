// Copyright 2022 Google LLC
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

import AndroidAutoLogger
import Foundation
@_implementationOnly import AndroidAutoCompanionProtos

/// Factory which makes an out of band token provider for an accessory.
///
/// Hides details of the underlying support so it's safe to call from anywhere.
struct AccessoryOutOfBandTokenProviderFactory {
  private static let log = Logger(for: AccessoryOutOfBandTokenProviderFactory.self)

  /// Make new provider if supported on the platform.
  ///
  /// - Returns: The new provider or `nil` if not supported on the platform.
  func makeProvider() -> OutOfBandTokenProvider? {
    #if canImport(ExternalAccessory)
      return AccessoryOutOfBandTokenProvider()
    #else
      return nil
    #endif
  }
}
