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

import CoreBluetooth
import Foundation

/// Factory for making the reconnection helpers.
protocol ReconnectionHelperFactory {
  /// Make a helper of the appropriate version depending on the advertisement.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral for which the reconnection is being attempted.
  ///   - advertisementData: The advertisement data associated with the peripheral discovery.
  ///   - associatedCars: The cars among which we should test for a match against the advertisement.
  ///   - uuidConfig: A configuration for common UUIDs.
  ///   - authenticator: Authenticator to use.
  /// - Throws: An error if either the service doesn't match what's expected or none of the
  /// associated cars match against the advertisement.
  @MainActor static func makeHelper(
    peripheral: AnyPeripheral,
    advertisementData: [String: Any],
    associatedCars: Set<Car>,
    uuidConfig: UUIDConfig,
    authenticator: CarAuthenticator.Type
  ) throws -> ReconnectionHelper
}

/// Factory for making reconnection helpers based on the advertisement.
struct ReconnectionHelperFactoryImpl: ReconnectionHelperFactory {
  /// Make a helper of the appropriate version depending on the advertisement.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral for which the reconnection is being attempted.
  ///   - advertisementData: The advertisement data associated with the peripheral discovery.
  ///   - associatedCars: The cars among which we should test for a match against the advertisement.
  ///   - uuidConfig: A configuration for common UUIDs.
  ///   - authenticator: Authenticator to use.
  /// - Throws: An error if either the service doesn't match what's expected or none of the
  /// associated cars match against the advertisement.
  @MainActor static func makeHelper(
    peripheral: AnyPeripheral,
    advertisementData: [String: Any],
    associatedCars: Set<Car>,
    uuidConfig: UUIDConfig,
    authenticator: CarAuthenticator.Type
  ) throws -> ReconnectionHelper {
    guard let serviceUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? NSArray
    else {
      throw CommunicationManagerError.serviceNotFound
    }

    if serviceUUIDs.contains(uuidConfig.reconnectionUUID(for: .v1)) {
      return ReconnectionHelperV1(peripheral: peripheral)
    }

    // It must be version 2, so make sure the advertisement is consistent.
    guard let dataContents = advertisementData[CBAdvertisementDataServiceDataKey] as? NSDictionary,
      let adData = dataContents[uuidConfig.reconnectionDataUUID] as? NSData
    else {
      return ReconnectionHelperV2(
        peripheral: peripheral,
        cars: associatedCars,
        authenticatorType: authenticator
      )
    }

    // Attempt to find an associated car that authenticates the information in the advertisement.
    guard
      let helper = ReconnectionHelperV2(
        peripheral: peripheral,
        advertisementData: adData as Data,
        cars: associatedCars,
        authenticatorType: authenticator
      )
    else {
      throw CommunicationManagerError.notAssociated
    }

    return helper
  }
}
