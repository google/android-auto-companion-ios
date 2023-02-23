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
import AndroidAutoMessageStream
import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// Mock `AssociationMessageHelper`.
@MainActor final public class AssociationMessageHelperMock {
  // MARK: - Method call checks
  public var startCalled = false
  public var handleMessageCalled = false
  public var messageDidSendSuccessfullyCalled = false
  public var onEncryptionEstablishedCalled = false
  public var onPairingCodeDisplayedCalled = false
  public var onRequiresPairingVerificationCalled = false

  // MARK: Basic Requirements

  static public let log = Logger(for: AssociationMessageHelperMock.self)

  private let messageStream: MessageStream
  public let associator: Associator

  public init(_ associator: Associator, messageStream: MessageStream) {
    self.associator = associator
    self.messageStream = messageStream
  }

  public func performEncryptionFlow() {
    associator.carId = "Test"
    associator.establishEncryption(using: messageStream)
  }

  public func performEncryptionAndPairingFlow() {
    performEncryptionFlow()
    try! associator.notifyPairingCodeAccepted()
  }
}

// MARK: - AssociationMessageHelper
extension AssociationMessageHelperMock: AssociationMessageHelper {
  public func start() {
    startCalled = true
  }

  public func handleMessage(_ message: Data, params: MessageStreamParams) {
    handleMessageCalled = true
  }

  public func messageDidSendSuccessfully() {
    messageDidSendSuccessfullyCalled = true
  }

  public func onRequiresPairingVerification(_ verificationToken: SecurityVerificationToken) {
    associator.displayPairingCode(verificationToken.pairingCode)
    onRequiresPairingVerificationCalled = true
  }

  public func onPairingCodeDisplayed() {
    onPairingCodeDisplayedCalled = true
  }

  public func onEncryptionEstablished() {
    onEncryptionEstablishedCalled = true
  }
}
