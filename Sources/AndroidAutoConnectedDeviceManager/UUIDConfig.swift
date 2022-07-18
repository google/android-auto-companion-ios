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

@_implementationOnly import AndroidAutoMessageStream
import CoreBluetooth
import Foundation

/// Holds common methods and properties related to service and characteristic UUIDs that are
/// scanned for and inspected throughout this library.
@available(watchOS 6.0, *)
class UUIDConfig {
  static let associationUUIDKey = "AssociationServiceUUID"
  static let associationDataUUIDKey = "AssociationDataUUID"
  static let reconnectionUUIDKey = "ReconnectionServiceUUID"
  static let reconnectionDataUUIDKey = "ReconnectionDataUUID"

  /// The default UUID to scan for when associating.
  private static let defaultAssociationServiceUUID = "5e2a68a4-27be-43f9-8d1e-4546976fabd7"

  /// The default service UUID to scan for with security version 2.
  ///
  /// This UUID is the Google Manufacturer Specific ID as outlined on
  /// go/google-ble-manufacturer-data-format.
  private static let defaultSecurityVersion2ServiceUUID = "000000e0-0000-1000-8000-00805f9b34fb"

  /// The UUID within the advertisement data that contains information needed for reconnection
  /// and association.
  ///
  /// This UUID is only valid for association with an unbundled IHU application. Due to the
  /// limits on advertising size, the name is now stored in the scan response and retrievable with
  /// this UUID.
  ///
  /// For reconnection, this value is only valid for security version 2.
  ///
  /// See go/google-ble-manufacturer-data-format and the "Google Manufacturer Data Type" for details
  /// on this value.
  private static let defaultDataUUID = "00000020-0000-1000-8000-00805f9b34fb"

  /// The characteristic UUID that should be used to listen for messages that the car is
  /// sending.
  static let readCharacteristicUUID = CBUUID(string: "5e2a68a5-27be-43f9-8d1e-4546976fabd7")

  /// The characteristic UUID that should be used to write messages to the car.
  static let writeCharacteristicUUID = CBUUID(string: "5e2a68a6-27be-43f9-8d1e-4546976fabd7")

  /// The characteristic UUID for the peripheral advertisement data.
  static let advertisementCharacteristicUUID =
    CBUUID(string: "24289b40-af40-4149-a5f4-878ccff87566")

  private let reconnectionV2UUID: CBUUID

  /// The service UUID that should be used as the scan filter when scanning for cars that are
  /// advertising for association.
  let associationUUID: CBUUID

  /// The UUID to use to as a key into the advertisement packet for any data needed for
  /// association.
  let associationDataUUID: CBUUID

  /// The UUID to use to as a key into the advertisement packet for any data needed for
  /// reconnection.
  let reconnectionDataUUID: CBUUID

  /// The list of supported UUIDs that should be scanned for when attempting to reconnect a car.
  var supportedReconnectionUUIDs: [CBUUID] {
    return [reconnectionUUID(for: .v2), reconnectionUUID(for: .v1)]
  }

  init(plistLoader: PListLoader) {
    let overlayValues = plistLoader.loadOverlayValues()
    let overlayAssociationUUID = overlayValues[Self.associationUUIDKey] as? String
    let overlayReconnectionUUID = overlayValues[Self.reconnectionUUIDKey] as? String
    let overlayReconnectionDataUUID = overlayValues[Self.reconnectionDataUUIDKey] as? String
    let overlayAssociationDataUUID = overlayValues[Self.associationDataUUIDKey] as? String

    associationUUID =
      CBUUID(string: overlayAssociationUUID ?? Self.defaultAssociationServiceUUID)
    associationDataUUID =
      CBUUID(string: overlayAssociationDataUUID ?? Self.defaultDataUUID)
    reconnectionV2UUID =
      CBUUID(string: overlayReconnectionUUID ?? Self.defaultSecurityVersion2ServiceUUID)
    reconnectionDataUUID =
      CBUUID(string: overlayReconnectionDataUUID ?? Self.defaultDataUUID)
  }

  /// Returns the service UUID that corresponds to the given security version.
  func reconnectionUUID(for version: MessageSecurityVersion) -> CBUUID {
    switch version {
    case .v1:
      // For version 1, the device ID serves as the service UUID to scan for.
      return DeviceIdManager.deviceId
    case .v2, .v3, .v4:
      return reconnectionV2UUID
    }
  }
}
