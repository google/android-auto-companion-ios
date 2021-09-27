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
import AndroidAutoLogger
import Foundation
import AndroidAutoCompanionProtos

private typealias VersionExchange = Com_Google_Companionprotos_VersionExchange

/// Resolver of the messaging protocol to use.
@available(iOS 10.0, *)
public class BLEVersionResolverImpl: NSObject, BLEVersionResolver {
  private static let logger = Logger(
    subsystem: "com.google.ios.aae.trustagentclient",
    category: "BLEVersionResolverImpl"
  )
  // The supported versions for the communication and security protocol.
  //
  // Note: using Int32 because this is what is defined in the proto.
  private static let minMessagingVersion: Int32 = 2
  private static let maxMessagingVersion: Int32 = 3

  private static let minSecurityVersion: Int32 = 1
  private static let maxSecurityVersion: Int32 = 2

  private var peripheral: BLEPeripheral?
  private var readCharacteristic: BLECharacteristic?
  private var writeCharacteristic: BLECharacteristic?

  public weak var delegate: BLEVersionResolverDelegate?

  /// Communicates with the given peripheral and resolves the BLE message stream version to use
  /// based on the result.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to resolve versions with.
  ///   - readCharacteristic: The characteristic on the peripheral it will write to.
  ///   - writeCharacteristic: The characteristic on the peripheral to write to.
  public func resolveVersion(
    with peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic
  ) {
    self.peripheral = peripheral
    self.readCharacteristic = readCharacteristic
    self.writeCharacteristic = writeCharacteristic

    peripheral.delegate = self
    peripheral.setNotifyValue(true, for: readCharacteristic)

    sendVersionExchangeProto(to: peripheral, writeCharacteristic: writeCharacteristic)
  }

  /// Verifies the version exchange from the given message and notifies any delegates of the result.
  private func resolveVersion(_ versionExchange: VersionExchange, for peripheral: BLEPeripheral) {
    guard
      let securityVersion = try? resolveSecurityVersion(from: versionExchange, for: peripheral)
    else {
      delegate?.bleVersionResolver(self, didEncounterError: .versionNotSupported, for: peripheral)
      return
    }

    guard
      let streamVersion = try? resolveMessagingVersion(from: versionExchange, for: peripheral)
    else {
      delegate?.bleVersionResolver(self, didEncounterError: .versionNotSupported, for: peripheral)
      return
    }

    peripheral.delegate = nil

    // This shouldn't be nil, but double-check because it's optional.
    if readCharacteristic != nil {
      peripheral.setNotifyValue(false, for: readCharacteristic!)
    }

    delegate?.bleVersionResolver(
      self,
      didResolveStreamVersionTo: streamVersion,
      securityVersionTo: securityVersion,
      for: peripheral
    )

    self.peripheral = nil
    readCharacteristic = nil
    writeCharacteristic = nil
  }

  /// Returns the maximum supported version for the given `peripheral` based off the given
  /// `versionExchange` or throw an error if no versions are supported.
  private func resolveSecurityVersion(
    from versionExchange: VersionExchange,
    for peripheral: BLEPeripheral
  ) throws -> BLEMessageSecurityVersion {
    // Use the max security version supported by both sides.
    let maxJointlySupportedSecurityVersion =
      min(Self.maxSecurityVersion, versionExchange.maxSupportedSecurityVersion)

    // Guard that the maximum jointly supported security version meets the minimum version
    // specified in the version exchange.
    guard maxJointlySupportedSecurityVersion >= versionExchange.minSupportedSecurityVersion
    else {
      Self.logger.error.log(
        """
        No supported security version. \
        Min security version: \(versionExchange.minSupportedSecurityVersion)
        """
      )

      throw BLEVersionResolverError.versionNotSupported
    }

    // Get our security version that matches the max jointly supported security version. Guard that
    // this max jointly supported version is one that exists as a BLEMessageSecurityVersion.
    guard
      let securityVersion = BLEMessageSecurityVersion(rawValue: maxJointlySupportedSecurityVersion)
    else {
      Self.logger.error.log(
        """
        No supported security version. \
        Max security version: \(versionExchange.maxSupportedSecurityVersion)"
        """
      )

      throw BLEVersionResolverError.versionNotSupported
    }

    return securityVersion
  }

  private func resolveMessagingVersion(
    from versionExchange: VersionExchange,
    for peripheral: BLEPeripheral
  ) throws -> MessageStreamVersion {
    let maxVersion = min(
      BLEVersionResolverImpl.maxMessagingVersion,
      versionExchange.maxSupportedMessagingVersion
    )

    let minVersion = max(
      BLEVersionResolverImpl.minMessagingVersion,
      versionExchange.minSupportedMessagingVersion
    )

    // This should only happen if the received proto itself is not well-formed.
    guard maxVersion >= minVersion else {
      Self.logger.error.log(
        """
        Malformed messaging version. \
        Max version (\(versionExchange.maxSupportedMessagingVersion)) is not >= min \
        (\(versionExchange.minSupportedMessagingVersion))
        """
      )
      throw BLEVersionResolverError.versionNotSupported
    }

    // Use the maximum supported version. Only 2 versions supported in this resolver at this time.
    switch maxVersion {
    case 3:
      // Version 3 is version 2 plus support for compression.
      return .v2(true)
    case 2:
      return .v2(false)
    default:
      Self.logger.error.log(
        """
        No supported messaging version. Min/Max messaging version: \
        (\(versionExchange.minSupportedMessagingVersion), \
        \(versionExchange.maxSupportedMessagingVersion))
        """
      )
      throw BLEVersionResolverError.versionNotSupported
    }
  }

  private func sendVersionExchangeProto(
    to peripheral: BLEPeripheral,
    writeCharacteristic: BLECharacteristic
  ) {
    guard let serializedProto = try? createVersionExchangeProto().serializedData() else {
      // This shouldn't fail because nothing dynamic is going into the proto.
      Self.logger.error.log("Could not serialized version exchange proto")
      notifyDelegateOfError(.failedToCreateProto, for: peripheral)
      return
    }

    Self.logger.log("Sending supported versions to car \(peripheral.logName)")

    peripheral.writeValue(serializedProto, for: writeCharacteristic)
  }

  /// Returns the version exchange proto that should be sent to the vehicle or `nil` if there was
  /// an error during the creation of the proto.
  ///
  /// If there was an error, the delegate is notified.
  private func createVersionExchangeProto() -> VersionExchange {
    var versionExchange = VersionExchange()

    versionExchange.maxSupportedMessagingVersion = BLEVersionResolverImpl.maxMessagingVersion
    versionExchange.minSupportedMessagingVersion = BLEVersionResolverImpl.minMessagingVersion
    versionExchange.maxSupportedSecurityVersion = BLEVersionResolverImpl.maxSecurityVersion
    versionExchange.minSupportedSecurityVersion = BLEVersionResolverImpl.minSecurityVersion

    return versionExchange
  }

  private func notifyDelegateOfError(
    _ error: BLEVersionResolverError,
    for peripheral: BLEPeripheral
  ) {
    delegate?.bleVersionResolver(self, didEncounterError: .timedOut, for: peripheral)
  }
}

// MARK: - BLEPeripheralDelegate

@available(iOS 10.0, *)
extension BLEVersionResolverImpl: BLEPeripheralDelegate {
  public func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    guard error == nil else {
      Self.logger.error.log("Error during update: \(error!.localizedDescription)")
      delegate?.bleVersionResolver(self, didEncounterError: .failedToRead, for: peripheral)
      return
    }

    guard let message = characteristic.value else {
      Self.logger.error.log("Empty message from peripheral: \(peripheral.logName)")
      delegate?.bleVersionResolver(self, didEncounterError: .emptyResponse, for: peripheral)
      return
    }

    guard let versionExchange = try? VersionExchange(serializedData: message) else {
      Self.logger.error.log("Cannot serialize a version exchange proto from message")

      delegate?.bleVersionResolver(self, didEncounterError: .failedToParseResponse, for: peripheral)
      return
    }

    resolveVersion(versionExchange, for: peripheral)
  }

  public func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral) {
    // No-op. Only one message needs to be written.
  }

  public func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?) {
    // No-op. Not discovering services.
  }

  public func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  ) {
    // No-op. Not discovering characteristics.
  }
}
