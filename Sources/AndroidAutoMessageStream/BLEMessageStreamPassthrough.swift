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

/// A message stream that will not actually chunk any messages.
///
/// It will assume that all messages will fit and directly call a write to the peripheral it is
/// initialized with. It will also assume all messages from the peripheral are complete messages.
class BLEMessageStreamPassthrough: NSObject, BLEMessageStream {
  private static let log = Logger(for: BLEMessageStreamPassthrough.self)

  // This force-unwrap is safe as the UUID string is valid and cannot change.
  private static let defaultRecipient = UUID(uuidString: "B75D6A81-635B-4560-BD8D-9CDF83F32AE7")!

  public let version = MessageStreamVersion.passthrough

  public let peripheral: BLEPeripheral
  public let readCharacteristic: BLECharacteristic
  public let writeCharacteristic: BLECharacteristic

  public var messageEncryptor: MessageEncryptor?

  public weak var delegate: MessageStreamDelegate?

  var isValid: Bool {
    guard let readServiceUUID = readCharacteristic.serviceUUID else { return false }
    guard let writeServiceUUID = writeCharacteristic.serviceUUID else { return false }

    return !peripheral.isServiceInvalidated(uuids: [readServiceUUID, writeServiceUUID])
  }

  /// Debug description for reading.
  var readingDebugDescription: String {
    "Read characteristic with uuid: \(readCharacteristic.uuid.uuidString)"
  }

  /// Debug description for writing.
  var writingDebugDescription: String {
    "Write characteristic with uuid: \(writeCharacteristic.uuid.uuidString)"
  }

  /// Creates a stream with the given peripheral.
  ///
  /// - Parameters:
  ///   - peripheral: The peripheral to stream messages with.
  ///   - readCharacteristic: The characteristic to listen for new messages on.
  ///   - writeCharacteristic: The characteristic to write messages to.
  public init(
    peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic
  ) {
    self.peripheral = peripheral
    self.readCharacteristic = readCharacteristic
    self.writeCharacteristic = writeCharacteristic

    // "self" can only be used for something other than referencing fields after init() has been
    // called.
    super.init()
    peripheral.delegate = self
    peripheral.setNotifyValue(true, for: readCharacteristic)
  }

  /// Writes the given message to the peripheral associated with this stream.
  ///
  /// This implementation is a passthrough, so no message chunking will be performed.
  ///
  /// - Parameter message: The message to write.
  public func writeMessage(_ message: Data, params: MessageStreamParams) {
    peripheral.writeValue(message, for: writeCharacteristic)
  }

  /// Writes the given message to the peripheral associated with this stream.
  ///
  /// This implementation is a passthrough, so no message chunking or encryption will be performed.
  ///
  /// - Parameter message: The message to write.
  public func writeEncryptedMessage(_ message: Data, params: MessageStreamParams) throws {
    peripheral.writeValue(message, for: writeCharacteristic)
  }

  private func logUpdateError(_ error: Error, for characteristic: BLECharacteristic) {
    Self.log.error(
      """
      Error during update value for characteristic (\(characteristic.uuid.uuidString)): \
      \(error.localizedDescription)
      """
    )
  }

  private func notifyWriteError(_ error: Error, for characteristic: BLECharacteristic) {
    Self.log.error(
      """
      Error during write for characteristic (\(characteristic.uuid.uuidString)): \
      \(error.localizedDescription)
      """
    )

    delegate?.messageStream(
      self,
      didEncounterWriteError: error,
      to: BLEMessageStreamPassthrough.defaultRecipient
    )
  }
}

// MARK: - BLEPeripheralDelegate

extension BLEMessageStreamPassthrough: BLEPeripheralDelegate {
  public func peripheral(
    _ peripheral: BLEPeripheral,
    didUpdateValueFor characteristic: BLECharacteristic,
    error: Error?
  ) {
    guard error == nil else {
      logUpdateError(error!, for: characteristic)
      return
    }

    guard let message = characteristic.value else {
      // An empty message is not necessarily an error. Just continue waiting and see if the
      // characteristic updates to a valid one.
      Self.log.debug("Received empty message from characteristic \(characteristic.uuid.uuidString)")
      return
    }

    delegate?.messageStream(
      self,
      didReceiveMessage: message,
      params: MessageStreamParams(
        recipient: BLEMessageStreamPassthrough.defaultRecipient,
        operationType: .clientMessage
      )
    )
  }

  public func peripheralIsReadyToWrite(_ peripheral: BLEPeripheral) {
    delegate?.messageStreamDidWriteMessage(
      self,
      to: BLEMessageStreamPassthrough.defaultRecipient
    )
  }

  public func peripheral(_ peripheral: BLEPeripheral, didDiscoverServices error: Error?) {
    // No-op.
  }

  public func peripheral(
    _ peripheral: BLEPeripheral,
    didDiscoverCharacteristicsFor service: BLEService,
    error: Error?
  ) {
    // No-op.
  }
}
