// Copyright 2024 Google LLC
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

private import AndroidAutoAccountTransferCore
public import AndroidAutoConnectedDeviceManager
private import AndroidAutoLogger
public import Foundation

/// A feature that requests AccountTransfer to use Magic Wand.
///
/// Messages from Magic Wand are handled by SecondDeviceSignInUrlManager.
public class AccountTransferManager: FeatureManager {
  private static let log = Logger(for: AccountTransferManager.self)
  private static let recipientUUID = UUID(uuidString: "32bcc149-af7e-58b9-4346-0e0ae76b6737")!

  public override var featureID: UUID {
    return Self.recipientUUID
  }

  private lazy var messageHandler = AccountTransferMessageHandler(self)

  public override func onMessageReceived(_ message: Data, from car: Car) {
    Self.log.info("Received account transfer message.")

    do {
      try messageHandler.handleMessage(message, from: car)
    } catch {
      Self.log.error("Error processing message: \(error.localizedDescription)")
    }
  }
}

/// Retroactive conformance to Messenger for sending messages from within the handler.
extension AccountTransferManager: Messenger {}
