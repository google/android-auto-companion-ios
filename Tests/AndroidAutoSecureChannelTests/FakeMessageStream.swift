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

import AndroidAutoConnectedDeviceTransport
import AndroidAutoConnectedDeviceTransportFakes
import AndroidAutoLogger
import AndroidAutoMessageStream
import Foundation

/// A message stream that stores any messages to be written in a local list for assertion.
///
/// This stream also exposes methods to toggle if writing messages should succeed or not.
class FakeMessageStream: NSObject, MessageStream {
  private static let log = Logger(for: FakeMessageStream.self)

  // This force-unwrap is safe as the UUID string is valid and cannot change.
  private static let defaultRecipient = UUID(uuidString: "ba4bdcfb-b5dd-4560-9e03-1444bcb0fcb6")!

  public let peripheral: AnyTransportPeripheral
  public let version: MessageStreamVersion

  public var isValid: Bool { true }

  var readingDebugDescription = ""
  var writingDebugDescription = ""

  public var messageEncryptor: MessageEncryptor? = nil

  /// Messages that have been delivered through a call to `writeMessage(_:params:)` or
  /// `writeEncryptedMessage(_:params:)`.
  public var writtenData: [Data] = []

  /// A closure that will be invoked when there is a call to `writeMessage(_:params:)` or
  /// `writeEncryptedMessage(_:params:)`.
  ///
  /// This closure should return `true` if a `writeMessage` call should succeed.
  public var writeMessageSucceeds: () -> Bool = { true }

  public weak var delegate: MessageStreamDelegate?

  public init(peripheral: AnyTransportPeripheral, version: MessageStreamVersion = .passthrough) {
    self.peripheral = peripheral
    self.version = version
  }

  public func writeMessage(_ message: Data, params: MessageStreamParams) throws {
    try writeMessageInternal(message, params: params)
  }

  public func writeEncryptedMessage(_ message: Data, params: MessageStreamParams) throws {
    try writeMessageInternal(message, params: params)
  }

  private func writeMessageInternal(_ message: Data, params: MessageStreamParams) throws {
    guard writeMessageSucceeds() else {
      throw makeFakeError()
    }

    writtenData.append(message)
  }

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}
