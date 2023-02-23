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

import Foundation

/// The possible errors that can result during an unlocking process.
public enum TrustAgentManagerError: Error {
  ///  Requested to enroll a specified car that was not currently connected.
  case carNotConnected

  /// An error has occurred during the generation the escrow token that needs to be sent to
  /// the head unit.
  ///
  /// Usually this error is transient, and the association flow can be kicked off again.
  case cannotGenerateToken

  /// An error occurred with the sending of the escrow token with the head unit.
  case cannotSendToken

  /// An error occurred during the storage of the handle.
  case cannotStoreHandle

  /// Error occurred during sending of a message.
  case cannotSendMessages

  /// The handle characteristic has sent an invalid handle.
  case invalidHandle

  /// There was an error during the sending of the unlock data to the car.
  case cannotSendCredentials

  /// A passcode has not been set, but either enrolling or unlocking was requested.
  case passcodeNotSet

  /// This device is locked, but unlocking has be requested
  case deviceLocked
}

/// A delegate to be notified of the current state of unlocking.
@MainActor public protocol TrustAgentManagerDelegate: AnyObject {
  /// Invoked when an enrollment has completed with an associated car.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The trust agent manager handling enrollment.
  ///   - car: The car that finished enrollment.
  ///   - initiatedFromCar: Whether the enrollment was initiated from the car or not.
  func trustAgentManager(
    _ trustAgentManager: TrustAgentManager, didCompleteEnrolling car: Car, initiatedFromCar: Bool)

  /// Invoked when an error is encountered during the enrollment of a car.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The trust agent manager handling enrollment.
  ///   - car: The car that encountered the error.
  ///   - error: The error that occurred.
  func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didEncounterEnrollingErrorFor car: Car,
    error: TrustAgentManagerError
  )

  /// Invoked when the given `car` has been un-enrolled from trusted device.
  ///
  /// The user will need to re-enroll in order for the feature to work. This method will only be
  /// invoked if the given `car` had previously been enrolled.
  ///
  /// If the user turned off this feature from the car, then `initiatedFromCar` will be `true`.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The trust agent manager handling enrollment.
  ///   - car: The car that has un-enrolled from trusted device.
  ///   - initiatedFromCar: Whether the car initiated the unenrollment.
  func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didUnenroll car: Car,
    initiatedFromCar: Bool
  )

  /// Invoked when the unlock process has started for a car.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The connection manager who is managing connections.
  ///   - car: The car that has started unlocking.
  func trustAgentManager(_ trustAgentManager: TrustAgentManager, didStartUnlocking car: Car)

  /// Called when an unlock request on a car has succeeded.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The unlock manager handling unlocking.
  ///   - car: The car to be unlocked.
  func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didSuccessfullyUnlock car: Car
  )

  /// Called when an unlock request on a car has resulted in an error.
  ///
  /// - Parameters:
  ///   - trustAgentManager: The unlock manager handling unlocking.
  ///   - car: The car to be unlocked.
  ///   - error: The error that occurred.
  func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didEncounterUnlockErrorFor car: Car,
    error: TrustAgentManagerError
  )
}
