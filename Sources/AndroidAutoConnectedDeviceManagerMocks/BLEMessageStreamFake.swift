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
import AndroidAutoMessageStream
import Foundation

/// A fake `BLEMessageStream` that stores written messages to internal arrays and exposes methods
/// to simulate a message received from a remote car.
public class BLEMessageStreamFake: BLEMessageStream {
  /// Automatically replies to written messages.
  public var autoReply: (message: Data, params: MessageStreamParams)? = nil

  public let version = MessageStreamVersion.passthrough

  public let peripheral: BLEPeripheral
  public var messageEncryptor: MessageEncryptor? = nil

  /// Debug description for reading.
  public var readingDebugDescription: String { "Fake Reading" }

  /// Debug description for writing.
  public var writingDebugDescription: String { "Fake Writing" }

  public weak var delegate: MessageStreamDelegate?

  /// Messages that have been written via a call to `writeMessage(_:params:)`
  public var writtenMessages: [WrittenMessage] = []

  /// Messages that have been written via a call to `writeEncryptedMessage(_:params:)`
  public var writtenEncryptedMessages: [WrittenMessage] = []

  public var isValid: Bool {
    return peripheral.state == .connected
  }

  public init(peripheral: BLEPeripheral) {
    self.peripheral = peripheral
  }

  // MARK: - BLEMessageStream implementation.

  public func writeMessage(_ message: Data, params: MessageStreamParams) throws {
    guard isValid else {
      throw makeFakeError()
    }
    writtenMessages.append(WrittenMessage(message: message, params: params))

    if let autoReply {
      Task {
        delegate?.messageStream(
          self, didReceiveMessage: autoReply.message, params: autoReply.params)
      }
    }
  }

  public func writeEncryptedMessage(_ message: Data, params: MessageStreamParams) throws {
    guard isValid else {
      throw makeFakeError()
    }
    writtenEncryptedMessages.append(WrittenMessage(message: message, params: params))

    if let autoReply {
      Task {
        delegate?.messageStream(
          self, didReceiveMessage: autoReply.message, params: autoReply.params)
      }
    }
  }

  // MARK: - Simulate message received methods.

  /// Simulates that the given message was received by a remote car.
  public func triggerMessageReceived(_ message: Data, params: MessageStreamParams) {
    delegate?.messageStream(self, didReceiveMessage: message, params: params)
  }

  /// Simulates an error when writing a message.
  public func triggerWriteError(to recipient: UUID) {
    delegate?.messageStream(self, didEncounterWriteError: makeFakeError(), to: recipient)
  }

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}

/// Encapsulates the data for a message that is written to the stream.
public struct WrittenMessage {
  public var message: Data
  public var params: MessageStreamParams
}
