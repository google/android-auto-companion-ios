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
import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// An implementation of a secure channel for testing purposes.
///
/// This class simply states that a secure channel has been established if its methods are called
/// in the correct order.
///
/// Encrypting and decrypting a message returns the same message.
final public class SecureBLEChannelMock: NSObject, SecureBLEChannel {
  public static let mockSavedSession = Data("SecureBLEChannelMockSavedSession".utf8)

  /// The state of the secure channel.
  private(set) public var state: SecureBLEChannelState = .uninitialized

  var messageStream: MessageStream?
  var savedSession: Data?

  /// A delegate that will be notified of various events with the secure channel.
  public var delegate: SecureBLEChannelDelegate?

  // Token used for verification.
  var verificationToken: SecurityVerificationToken = FakeVerificationToken()

  public var notifyPairingCodeAcceptedCalled = false

  /// Whether a secure session establishment should instantly notify any delegates of the pairing
  /// code to verify.
  ///
  /// If this value is `false`, then users of this mock should ensure that
  /// `notifyDelegateOfPairingCode()` is explicitly called.
  public var establishShouldInstantlyNotify = false

  /// Whether a call to `establish(using:withSavedSession)` should instantly notify any delegates
  /// that it was successful.
  ///
  /// If this value is `false`, then users of this mock should explicitly call
  /// `notifySavedSessionEstablished()`.
  public var savedSessionShouldInstantlyNotify = false

  public var establishWithSavedSessionCalled = false

  /// Whether a call to `saveSession` will throw an error or not.
  public var saveSessionSucceeds = true

  public func establish(using messageStream: MessageStream) throws {
    self.messageStream = messageStream

    // The SecureChannel needs to be a delegate of the message stream so that it can listen for
    // when message are received or sent. Setting this delegate will test if clients handle
    // setting themselves back as a delegate.
    messageStream.delegate = self

    state = .inProgress

    if establishShouldInstantlyNotify {
      delegate?.secureBLEChannel(
        self,
        requiresVerificationOf: verificationToken,
        messageStream: messageStream
      )
    }
  }

  public func establish(
    using messageStream: MessageStream,
    withSavedSession savedSession: Data
  ) throws {
    establishWithSavedSessionCalled = true

    // Note that the call to `saveSession()` will never fail in this mock.
    let expectedSavedSession = try! saveSession()

    guard savedSession == expectedSavedSession else {
      XCTFail("Invalid saved session passed.")

      // A generic error.
      throw NSError(domain: "", code: 0, userInfo: nil)
    }

    self.messageStream = messageStream

    // The SecureChannel needs to be a delegate of the message stream so that it can listen for
    // when message are received or sent. Setting this delegate will test if clients handle
    // setting themselves back as a delegate.
    messageStream.delegate = self

    if savedSessionShouldInstantlyNotify {
      notifySavedSessionEstablished()
    }
  }

  public func notifyPairingCodeAccepted() throws {
    guard let messageStream = messageStream else {
      XCTFail("notifyPairingCodeAccepted() called out of order. No messageStream set.")
      return
    }

    notifyPairingCodeAcceptedCalled = true

    state = .established

    delegate?.secureBLEChannel(self, establishedUsing: messageStream)

    self.messageStream = nil
  }

  public func saveSession() throws -> Data {
    guard saveSessionSucceeds else {
      // A generic error.
      throw NSError(domain: "", code: 0, userInfo: nil)
    }

    return SecureBLEChannelMock.mockSavedSession
  }

  /// Notifies any delegates on this mock that a secure session was established from a previously
  /// saved secure session.
  public func notifySavedSessionEstablished() {
    guard state != .established else {
      XCTFail("notifySavedSessionEstablished() called out of order. State is already established.")
      return
    }

    guard let messageStream = messageStream else {
      XCTFail("notifySavedSessionEstablished() called out of order. No messageStream set.")
      return
    }

    state = .established
    delegate?.secureBLEChannel(self, establishedUsing: messageStream)

    self.messageStream = nil
  }

  public func reset() {
    messageStream = nil
    verificationToken = FakeVerificationToken()

    notifyPairingCodeAcceptedCalled = false
    establishShouldInstantlyNotify = false

    savedSessionShouldInstantlyNotify = false
    establishWithSavedSessionCalled = false
  }
}

// MARK: - MessageStreamDelegate

extension SecureBLEChannelMock: MessageStreamDelegate {
  public func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {}

  public func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {}

  public func messageStreamDidWriteMessage(
    _ messageStream: MessageStream, to recipient: UUID
  ) {}

  public func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {}
}

/// Fake verification token.
private struct FakeVerificationToken: SecurityVerificationToken {
  static let defaultPairingCode = "000000"
  static let defaultOutOfBandVerificationData = Data(defaultPairingCode.utf8)

  /// Full backing data.
  let data: Data

  /// Human-readable visual pairing code.
  let pairingCode: String

  init() {
    self.data = Self.defaultOutOfBandVerificationData
    self.pairingCode = Self.defaultPairingCode
  }
}
