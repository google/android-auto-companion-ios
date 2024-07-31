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

public import AndroidAutoConnectedDeviceManager
private import AndroidAutoLogger
public import Foundation
public import RemoteSetup

/// A feature that transfers remote setup preferences to an automotive device.
public class RemoteSetupPreferenceManager: FeatureManager {
  private static let log = Logger(for: RemoteSetupPreferenceManager.self)
  private static let recipientUUID = UUID(uuidString: "3f112c6f-37b3-4a73-8505-1268394b409d")!

  public override var featureID: UUID {
    return Self.recipientUUID
  }

  private lazy var messageHandler = RemoteSetupPreferenceMessageHandler(self, logger: Logger.self)

  public override func onMessageReceived(_ message: Data, from car: Car) {
    Self.log.info("Received remote setup preference message")

    do {
      try messageHandler.handleMessage(message, from: car)
    } catch {
      Self.log.error("Error processing message \(error.localizedDescription)")
    }
  }
}

/// Retroactive conformance to Messenger for sending messages from within the handler.
extension RemoteSetupPreferenceManager: Messenger {}
