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

@testable import AndroidAutoConnectedDeviceManager

/// A mock `TrustAgentManagerDelegate` that can assert if its methods are called.
public class TrustAgentDelegateMock: TrustAgentManagerDelegate {
  public var didStartUnlockingCalled = false
  public var didFinishUnlockingCalled = false
  public var didEncounterErrorCalled = false
  public var didCompleteEnrollingCalled = false
  public var didEncounterEnrollingErrorCalled = false
  public var didUnenrollCalled = false

  public var enrolledCar: Car?
  public var enrollingErrorCar: Car?
  public var enrollingError: TrustAgentManagerError?

  public var unenrolledCar: Car?
  public var unenrollInitiatedFromCar = false

  public var didStartUnlockingCar: Car?
  public var didUnlockCar: Car?
  public var errorCar: Car?
  public var error: TrustAgentManagerError?

  public init() {}

  public func trustAgentManager(
    _ trustAgentManager: TrustAgentManager, didCompleteEnrolling car: Car, initiatedFromCar: Bool
  ) {
    didCompleteEnrollingCalled = true
    enrolledCar = car
  }

  public func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didEncounterEnrollingErrorFor car: Car,
    error: TrustAgentManagerError
  ) {
    didEncounterEnrollingErrorCalled = true
    enrollingErrorCar = car
    enrollingError = error
  }

  public func trustAgentManager(
    _ trustAgentManager: TrustAgentManager, didUnenroll car: Car, initiatedFromCar: Bool
  ) {
    didUnenrollCalled = true
    unenrolledCar = car
    unenrollInitiatedFromCar = initiatedFromCar
  }

  public func trustAgentManager(_ trustAgentManager: TrustAgentManager, didStartUnlocking car: Car)
  {
    didStartUnlockingCalled = true
    didStartUnlockingCar = car
  }

  public func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didSuccessfullyUnlock car: Car
  ) {
    didFinishUnlockingCalled = true
    didUnlockCar = car
  }

  public func trustAgentManager(
    _ trustAgentManager: TrustAgentManager,
    didEncounterUnlockErrorFor car: Car,
    error: TrustAgentManagerError
  ) {
    didEncounterErrorCalled = true
    errorCar = car
    self.error = error
  }
}
