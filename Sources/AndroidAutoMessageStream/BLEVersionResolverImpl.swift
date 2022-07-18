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
private typealias CapabilitiesExchange = Com_Google_Companionprotos_CapabilitiesExchange

/// Result of successful resolution.
private struct ExchangeResolution {
  let streamVersion: MessageStreamVersion
  let securityVersion: MessageSecurityVersion
}

/// Result of a resolver exchange.
private enum ResolutionExchange {
  /// The exchange yielded a new exchange phase to execute.
  case nextPhase(ResolutionExchangeHandler)

  /// The exchange has been successfully resolved.
  case resolved(ExchangeResolution)

  /// The exchange has failed.
  case failure(BLEVersionResolverError)
}

/// Processes one resolution exchange in a sequence of exchanges.
private protocol ResolutionExchangeHandler {
  /// Resolve the received message.
  func resolveMessage(_: Data)
}

/// Processes message exchange.
private protocol MessageExchangeDelegate: AnyObject {
  var allowsCapabilitiesExchange: Bool { get }

  func writeMessage(_: Data)
  func process(_: ResolutionExchange)
}

/// Resolver of the messaging protocol to use.
public class BLEVersionResolverImpl: NSObject, BLEVersionResolver {
  private static let log = Logger(for: BLEVersionResolverImpl.self)

  private var peripheral: BLEPeripheral?
  private var readCharacteristic: BLECharacteristic?
  private var writeCharacteristic: BLECharacteristic?
  private var exchangeHandler: ResolutionExchangeHandler?

  fileprivate var allowsCapabilitiesExchange = false

  public weak var delegate: BLEVersionResolverDelegate?

  /// Communicates with the given peripheral and resolves the BLE message stream version to use
  /// based on the result.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to resolve versions with.
  ///   - readCharacteristic: The characteristic on the peripheral it will write to.
  ///   - writeCharacteristic: The characteristic on the peripheral to write to.
  ///   - allowsCapabilitiesExchange: Whether capabilities exchange is allowed (e.g. associating).
  public func resolveVersion(
    with peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic,
    allowsCapabilitiesExchange: Bool
  ) {
    self.peripheral = peripheral
    self.readCharacteristic = readCharacteristic
    self.writeCharacteristic = writeCharacteristic
    self.allowsCapabilitiesExchange = allowsCapabilitiesExchange

    let versionExchangeHandler = VersionExchangeHandler(
      peripheral: peripheral,
      delegate: self
    )
    self.exchangeHandler = versionExchangeHandler

    peripheral.delegate = self
    peripheral.setNotifyValue(true, for: readCharacteristic)

    versionExchangeHandler.sendVersionExchangeProto()
  }
}

// MARK: - MessageExchangeDelegate

extension BLEVersionResolverImpl: MessageExchangeDelegate {
  fileprivate func writeMessage(_ message: Data) {
    guard let writeCharacteristic = self.writeCharacteristic else {
      // This shouldn't ever happen as the characteristic gets set with `resolveVersion`.
      fatalError("Sending message for `nil` writeCharacteristic")
    }
    peripheral?.writeValue(message, for: writeCharacteristic)
  }

  fileprivate func process(_ exchange: ResolutionExchange) {
    guard let peripheral = self.peripheral else {
      // This shouldn't ever happen as the peripheral gets set with `resolveVersion`.
      fatalError("Processing exchange without a peripheral.")
    }

    // Process the next phase if there is one.
    if case let .nextPhase(nextHandler) = exchange {
      self.exchangeHandler = nextHandler
      return
    }

    peripheral.delegate = nil

    // This shouldn't be nil, but double-check because it's optional.
    if self.readCharacteristic != nil {
      peripheral.setNotifyValue(false, for: self.readCharacteristic!)
    }

    switch exchange {
    case .resolved(let resolution):
      Self.log(
        """
        Resolved versions. Stream: \(resolution.streamVersion), \
        Security: \(resolution.securityVersion)
        """
      )
      self.delegate?.bleVersionResolver(
        self,
        didResolveStreamVersionTo: resolution.streamVersion,
        securityVersionTo: resolution.securityVersion,
        for: peripheral
      )
    case .failure(let error):
      self.delegate?.bleVersionResolver(self, didEncounterError: error, for: peripheral)
    case .nextPhase(_):
      // The next phase is always handled up front and returns, so this line is unreachable.
      fatalError("nextPhase should be unreachable.")
    }

    self.peripheral = nil
    self.exchangeHandler = nil
    self.readCharacteristic = nil
    self.writeCharacteristic = nil
  }
}

// MARK: - BLEPeripheralDelegate

extension BLEVersionResolverImpl: BLEPeripheralDelegate {
  public func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    guard error == nil else {
      Self.log.error("Error during update: \(error!.localizedDescription)")
      delegate?.bleVersionResolver(self, didEncounterError: .failedToRead, for: peripheral)
      return
    }

    guard let message = characteristic.value else {
      Self.log.error("Empty message from peripheral: \(peripheral.logName)")
      delegate?.bleVersionResolver(self, didEncounterError: .emptyResponse, for: peripheral)
      return
    }

    exchangeHandler?.resolveMessage(message)
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

private struct VersionExchangeHandler: ResolutionExchangeHandler {
  private static let log = Logger(for: VersionExchangeHandler.self)

  // The supported versions for the communication and security protocol.
  //
  // Note: using Int32 because this is what is defined in the proto.
  private static let minMessagingVersion: Int32 = 2
  private static let maxMessagingVersion: Int32 = 3

  private static let minSecurityVersion: Int32 = 1
  private static let maxSecurityVersion: Int32 = 4

  /// Only security version that supports capabilities exchange.
  private static let capabilitiesExchangeSecurityVersion: Int32 = 3

  private let peripheral: BLEPeripheral
  private weak var delegate: MessageExchangeDelegate?

  init(peripheral: BLEPeripheral, delegate: MessageExchangeDelegate) {
    self.peripheral = peripheral
    self.delegate = delegate
  }

  func sendVersionExchangeProto() {
    guard let delegate = self.delegate else { return }

    guard let serializedProto = try? Self.createVersionExchangeProto().serializedData() else {
      // This shouldn't fail because nothing dynamic is going into the proto.
      Self.log.error("Could not serialize version exchange proto")
      delegate.process(.failure(.failedToCreateProto))
      return
    }

    Self.log("Sending supported versions to car \(peripheral.logName)")

    delegate.writeMessage(serializedProto)
  }

  // MARK: ResolutionExchangeHandler conformance
  func resolveMessage(_ message: Data) {
    guard let versionExchange = try? VersionExchange(serializedData: message) else {
      Self.log.error("Cannot serialize a version exchange proto from message")

      delegate?.process(.failure(.failedToParseResponse))
      return
    }

    resolveVersion(versionExchange)
  }

  // MARK: Private Methods

  /// Returns the version exchange proto that should be sent to the vehicle or `nil` if there was
  /// an error during the creation of the proto.
  ///
  /// If there was an error, the delegate is notified.
  private static func createVersionExchangeProto() -> VersionExchange {
    var versionExchange = VersionExchange()

    versionExchange.maxSupportedMessagingVersion = maxMessagingVersion
    versionExchange.minSupportedMessagingVersion = minMessagingVersion
    versionExchange.maxSupportedSecurityVersion = maxSecurityVersion
    versionExchange.minSupportedSecurityVersion = minSecurityVersion

    return versionExchange
  }

  /// Verifies the version exchange from the given message and notifies any delegates of the result.
  private func resolveVersion(_ versionExchange: VersionExchange) {
    guard let delegate = self.delegate else { return }

    guard
      let securityVersion = try? resolveSecurityVersion(from: versionExchange)
    else {
      delegate.process(.failure(.versionNotSupported))
      return
    }

    let allowsCapabilitiesExchange = delegate.allowsCapabilitiesExchange
    let shouldExchangeCapabilities =
      allowsCapabilitiesExchange
      && securityVersion.rawValue == Self.capabilitiesExchangeSecurityVersion

    guard
      let streamVersion = try? resolveMessagingVersion(from: versionExchange)
    else {
      delegate.process(.failure(.versionNotSupported))
      return
    }

    let resolution = ExchangeResolution(
      streamVersion: streamVersion, securityVersion: securityVersion)
    guard shouldExchangeCapabilities else {
      delegate.process(.resolved(resolution))
      return
    }

    // Exchange capabilities.
    let capabilitiesExchanger = EmptyCapabilitiesExchangeHandler(
      resolution: resolution,
      peripheral: peripheral,
      delegate: delegate
    )
    delegate.process(.nextPhase(capabilitiesExchanger))
    capabilitiesExchanger.sendCapabilities()
  }

  /// Returns the maximum supported version for the given `peripheral` based off the given
  /// `versionExchange` or throw an error if no versions are supported.
  private func resolveSecurityVersion(
    from versionExchange: VersionExchange
  ) throws -> MessageSecurityVersion {
    // Use the max security version supported by both sides.
    let maxJointlySupportedSecurityVersion =
      min(Self.maxSecurityVersion, versionExchange.maxSupportedSecurityVersion)

    // Guard that the maximum jointly supported security version meets the minimum version
    // specified in the version exchange.
    guard maxJointlySupportedSecurityVersion >= versionExchange.minSupportedSecurityVersion
    else {
      Self.log.error(
        """
        No supported security version. \
        Min security version: \(versionExchange.minSupportedSecurityVersion)
        """
      )

      throw BLEVersionResolverError.versionNotSupported
    }

    // Get our security version that matches the max jointly supported security version. Guard that
    // this max jointly supported version is one that exists as a MessageSecurityVersion.
    guard
      let securityVersion = MessageSecurityVersion(rawValue: maxJointlySupportedSecurityVersion)
    else {
      Self.log.error(
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
    from versionExchange: VersionExchange
  ) throws -> MessageStreamVersion {
    let maxVersion = min(
      Self.maxMessagingVersion,
      versionExchange.maxSupportedMessagingVersion
    )

    let minVersion = max(
      Self.minMessagingVersion,
      versionExchange.minSupportedMessagingVersion
    )

    // This should only happen if the received proto itself is not well-formed.
    guard maxVersion >= minVersion else {
      Self.log.error(
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
      Self.log.error(
        """
        No supported messaging version. Min/Max messaging version: \
        (\(versionExchange.minSupportedMessagingVersion), \
        \(versionExchange.maxSupportedMessagingVersion))
        """
      )
      throw BLEVersionResolverError.versionNotSupported
    }
  }
}

/// Handles capabilities exchange.
///
/// Sends empty capabilities to satisfy V3 security requirements. Since V4 deprecates capabilities
/// exchange, we don't need to build it out any further.
private struct EmptyCapabilitiesExchangeHandler: ResolutionExchangeHandler {
  private static let log = Logger(for: EmptyCapabilitiesExchangeHandler.self)

  private let resolution: ExchangeResolution
  private let peripheral: BLEPeripheral
  private weak var delegate: MessageExchangeDelegate?

  init(
    resolution: ExchangeResolution,
    peripheral: BLEPeripheral,
    delegate: MessageExchangeDelegate
  ) {
    self.resolution = resolution
    self.peripheral = peripheral
    self.delegate = delegate
  }

  func sendCapabilities() {
    guard let delegate = self.delegate else { return }

    // Sends empty capabilities to meet the minimal requirements for the exchange.
    guard let serializedProto = try? CapabilitiesExchange().serializedData() else {
      // This shouldn't fail because nothing dynamic is going into the proto.
      Self.log.error("Could not serialize capabilities exchange proto")
      delegate.process(.failure(.failedToCreateProto))
      return
    }

    Self.log("Sending empty capabilities to car \(peripheral.logName)")

    delegate.writeMessage(serializedProto)
  }

  // MARK: ResolutionExchangeHandler conformance

  func resolveMessage(_ message: Data) {
    // Ignoring capabilities, so just forward the previous resolution.
    delegate?.process(.resolved(resolution))
  }
}
