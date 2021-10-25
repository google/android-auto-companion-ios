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

import AndroidAutoCoreBluetoothProtocols
import Foundation

/// A delegate to be notified of the result of a version exchange.
public protocol BLEVersionResolverDelegate: AnyObject {
  /// Called upon a successful version exchange.
  ///
  /// - Parameters:
  ///   - bleVersionResolver: The resolver that performed the version exchange.
  ///   - version: The BLE messaging stream version that should be used.
  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didResolveStreamVersionTo streamVersion: MessageStreamVersion,
    securityVersionTo securityVersion: MessageSecurityVersion,
    for peripheral: BLEPeripheral
  )

  /// Called if there was an error during the version exchange.
  ///
  /// - Parameters:
  ///   - bleVersionResolver: The resolver that performed the version exchange.
  ///   - error: The error during the exchange.
  ///   - peripheral: The peripheral for which the resolver was acting.
  func bleVersionResolver(
    _ bleVersionResolver: BLEVersionResolver,
    didEncounterError error: BLEVersionResolverError,
    for peripheral: BLEPeripheral
  )
}

/// Possible errors that can result from the version exchange.
public enum BLEVersionResolverError: Error {
  case failedToCreateProto
  case failedToWrite
  case failedToRead
  case emptyResponse
  case failedToParseResponse
  case versionNotSupported
  case timedOut
}

/// Determines which versions of the BLE messaging stream a peripheral supports and should be used.
public protocol BLEVersionResolver: AnyObject {
  var delegate: BLEVersionResolverDelegate? { get set }

  /// Communicates with the given peripheral and resolves the BLE message stream version to use
  /// based on the result.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to resolve versions with.
  ///   - readCharacteristic: The characteristic on the peripheral it will write to.
  ///   - writeCharacteristic: The characteristic on the peripheral to write to.
  func resolveVersion(
    with peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic,
    allowsCapabilitiesExchange: Bool
  )
}
