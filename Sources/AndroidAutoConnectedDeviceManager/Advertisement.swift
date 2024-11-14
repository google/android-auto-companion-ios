// Copyright 2024 Google LLC
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

private import AndroidAutoLogger
@preconcurrency internal import CoreBluetooth
internal import Foundation

/// Extracts advertisement data from the advertisement dictionary and allows the data to be passed
/// safely across concurrency boundaries.
public struct Advertisement: Sendable {
  /// The length in bytes of the advertisement data that indicates whether the value should be
  /// converted to a string via UTF-8 encoding.
  ///
  /// If the length does not match, then the data should be converted to a hexadecimal representation.
  private static let advertisementLengthForUTF8Conversion = 8

  private static let log = Logger(for: Advertisement.self)

  /// Default advertised name
  private let defaultName: String?

  /// Advertisment data keyed by CBUUID.
  private let serviceData: [CBUUID: Data]

  /// Advertised services.
  let serviceUUIDs: [CBUUID]?

  init(data: [String: Any]) {
    defaultName = data[CBAdvertisementDataLocalNameKey] as? String

    var serviceData: [CBUUID: Data] = [:]
    if let rawServiceData = data[CBAdvertisementDataServiceDataKey] as? NSDictionary {
      for (key, adData) in rawServiceData {
        guard let key = key as? CBUUID else { continue }
        guard let adData = adData as? NSData else { continue }
        serviceData[key] = adData as Data
      }
    }
    self.serviceData = serviceData

    if let serviceUUIDs = data[CBAdvertisementDataServiceUUIDsKey] as? NSArray {
      self.serviceUUIDs = serviceUUIDs as? [CBUUID]
    } else {
      self.serviceUUIDs = nil
    }
  }

  /// Empty advertisement.
  init() {
    self.init(data: [:])
  }

  func resolveName(using uuidConfig: UUIDConfig) -> String? {
    // The advertised name can come from two sources. In newer versions, the name is stored in the
    // scan response and retrievable by the `associationDataUUID`. Otherwise, it's the standard
    // advertised name.
    guard let rawData = serviceData[uuidConfig.associationDataUUID] else {
      Self.log("Retrieving default advertised name from advertisement data.")

      // iOS will cache the name of the discovered peripheral if it is paired via Bluetooth. This
      // means `peripheral.name` might not be up to date. As a result, manually read the advertised
      // name to use as a backup name.
      return defaultName
    }

    if rawData.count == Self.advertisementLengthForUTF8Conversion {
      Self.log("Retrieving advertised name with association UUID using UTF-8.")
      return String(decoding: rawData, as: UTF8.self)
    }

    Self.log("Advertisement data of length \(rawData.count). Converting to hex value.")
    return rawData.hex
  }

  func reconnectionData(using uuidConfig: UUIDConfig) -> Data? {
    if let adData = serviceData[uuidConfig.reconnectionDataUUID] {
      return adData as Data
    } else {
      return nil
    }
  }

  /// Returns `true` if the advertised name is a new version and a prefix needs to be prepended.
  static func requiresNamePrefix(_ advertisedName: String) -> Bool {
    return advertisedName.count != advertisementLengthForUTF8Conversion
  }
}

extension Advertisement: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, Any)...) {
    let data: [String: Any] = elements.reduce(into: [:]) { accumulator, pair in
      accumulator[pair.0] = pair.1
    }
    self.init(data: data)
  }
}
