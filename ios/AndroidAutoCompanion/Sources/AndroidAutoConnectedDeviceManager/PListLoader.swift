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

import AndroidAutoLogger
import Foundation

/// A loader that is able to read values from a .plist file.
@available(iOS 10.0, watchOS 6.0, *)
protocol PListLoader {
  /// Returns a dictionary that represents values the OEM wishes to overlay over default values
  /// used within this library.
  ///
  /// If the OEM has not specified any configuration values or if there is an error loading the
  /// values, then an empty dictionary will be returned.
  func loadOverlayValues() -> Overlay
}

/// The default loader that will look for a `.plist` file with the file name passed to the
/// constructor and load the values from it.
@available(iOS 10.0, watchOS 6.0, *)
struct PListLoaderImpl: PListLoader {
  private static let logger = Logger(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "PListLoaderImpl"
  )

  private static let plistExtension = "plist"

  private let plistFileName: String

  /// Initializes this `PListLoader` to load values from a `.plist` file with the given name.
  init(plistFileName: String) {
    self.plistFileName = plistFileName
  }

  func loadOverlayValues() -> Overlay {
    guard
      let url =
        Bundle.main.url(forResource: plistFileName, withExtension: Self.plistExtension)
    else {
      Self.logger.log(
        "No custom overlay \(plistFileName).plist found. Returning empty configuration")
      return Overlay()
    }

    do {
      let data = try Data(contentsOf: url)

      guard
        let plist = try PropertyListSerialization.propertyList(
          from: data,
          format: nil
        ) as? [String: Any]
      else {
        Self.logger.log(
          """
          Custom overlay plist found, but not in expected key/value pair of String/Any. \
          Returning empty configuration
          """
        )
        return Overlay()
      }

      Self.logger.log("Custom overlay plist found: \(plist)")
      return Overlay(plist)
    } catch {
      Self.logger.error.log(
        "Encountered error loading custom overlay plist: \(error.localizedDescription)"
      )
      return Overlay()
    }
  }
}

/// Simple wrapper for the overlay key/value pairs.
///
/// This allows us to provide an extension point for adding convenient computed properties for the
/// associated keys/value pairs.
struct Overlay {
  /// The wrapped key/value pairs.
  let settings: [String: Any]

  /// Wrap the specified key/value pairs.
  ///
  /// - Parameter settings: The settings to wrap.
  init(_ settings: [String: Any] = [:]) {
    self.settings = settings
  }

  /// Simply forwards to the underlying settings dictionary.
  subscript(key: String) -> Any? { settings[key] }
}
