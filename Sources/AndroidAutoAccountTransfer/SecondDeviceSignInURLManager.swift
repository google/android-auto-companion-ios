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

import AndroidAutoAccountTransferCore
import AndroidAutoConnectedDeviceManager
import AndroidAutoLogger
import Foundation
import UIKit

/// Delegate that will be notified of sign-in URL received from a car.
@MainActor public protocol SecondDeviceSignInURLManagerDelegate: AnyObject {
  /// Invoked when a car has sent a sign-in URL.
  ///
  /// The delegate should immediately call `startSignIn` to start the sign-in process.
  /// If the sign-in process is not started, this function will be periodically (30s) invoked as
  /// the sign-in server refreshes the URL. Starting the sign-in will stop the refreshing.
  func secondDeviceSignInURLManagerDidReceiveURL(
    _ secondDeviceSignInURLManager: SecondDeviceSignInURLManager)

  /// Invoked when a car has received the user's credential.
  ///
  /// Receiving the credential is the last signal this manager receives. It is a strong indicator
  /// that the user has completed the process, but does not guarantee the success.
  /// The delegate can assume a success in most cases and proceed with the flow.
  func secondDeviceSignInURLManagerDidReceiveCredential(
    _ secondDeviceSignInURLManager: SecondDeviceSignInURLManager)
}

private typealias MessageHandler = SecondDeviceSignInURLMessageHandler<SecondDeviceSignInURLManager>

/// A feature that receives a Google sign-in URL from an associated car.
public class SecondDeviceSignInURLManager: FeatureManager {
  private static let log = Logger(for: SecondDeviceSignInURLManager.self)

  private static let recipientUUID = UUID(uuidString: "524a5d28-b208-449c-bb54-cd89498d3b1b")!

  private lazy var messageHandler = SecondDeviceSignInURLMessageHandler(self)

  public weak var delegate: SecondDeviceSignInURLManagerDelegate?

  public override var featureID: UUID {
    return Self.recipientUUID
  }

  public override func onMessageReceived(_ message: Data, from car: Car) {
    Self.log.info("Received message for second device sign-in URL feature.")

    do {
      let event = try messageHandler.handleMessage(message, from: car)
      switch event {
      case .receivedURL:
        delegate?.secondDeviceSignInURLManagerDidReceiveURL(self)
      case .receivedCredential:
        delegate?.secondDeviceSignInURLManagerDidReceiveCredential(self)
      @unknown default:
        Self.log.error("Unknown event: \(event) was handled. Ignored here.")
      }
    } catch MessageHandler.Error.malformedRequest(let summary) {
      Self.log.error(summary)
    } catch MessageHandler.Error.inconsistentState(let summary) {
      Self.log.error(summary)
    } catch MessageHandler.Error.mismatchedCars(let connectedCar, let car) {
      if let connectedCar {
        Self.log.error(
          "Received message from \(car) while connected to \(connectedCar). Ignored.")
      } else {
        Self.log.error("Received message from \(car) while none connected. Ignored.")
      }
    } catch {
      Self.log.error("Error handling message: \(error.localizedDescription)")
    }
  }

  /// Starts the Google sign-in flow with a web application.
  public func startSignIn(from uiViewController: UIViewController) -> Bool {
    let success = messageHandler.startSignIn(from: uiViewController)
    if success {
      Self.log("Starting sign-in.")
    } else {
      Self.log.error("No cached URL; could not start sign-in.")
    }
    return success
  }

  /// Notifies the car that the sign-in URL could not be started.
  ///
  /// For example, when the app is in the background, it should post a notification so the user
  /// can start the sign-in flow; but the app does not have notification permission.
  public func notifyFailure() {
    do {
      try messageHandler.notifyFailure()
    } catch {
      Self.log.error("Could not send faliure message. \(error.localizedDescription)")
    }
  }
}

extension SecondDeviceSignInURLManager {
  public enum UserNotification {
    public static let title = "Sign in with Google"
    public static let content = "Tap to sign in to your car"
  }
}

/// Retroactive conformance to Messenger for sending messages from within the handler.
extension SecondDeviceSignInURLManager: Messenger {}
