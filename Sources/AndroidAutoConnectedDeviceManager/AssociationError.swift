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

/// Possible errors that can occur during association.
public enum AssociationError: Error {
  /// An error of unknown cause.
  case unknown

  /// The car that is associating has disconnected and so association cannot be completed.
  case disconnected

  /// The association attempt to a remote car has timed out waiting for a response.
  case timedOut

  /// An error occurred during the discovery of services on the head unit.
  ///
  /// This error indicates that the service for association does not exist on the head unit.
  case cannotDiscoverServices

  /// An error occurred when trying to parse a message received from the head unit.
  case cannotParseMessage

  /// An error occurred when determining the format of messages to send to the car.
  case cannotSendMessages

  /// An error occurred during the storage of a device association.
  case cannotStoreAssociation

  /// An error occurred when discovering characteristics on the head unit.
  ///
  /// This error indicates that the characteristics that can receive the escrow token does not
  /// exist on the head unit.
  case cannotDiscoverCharacteristics

  /// The user has denied the pairing code on the head unit.
  ///
  /// This error indicates that the user has decided not to proceed with the association process
  /// and the flow should be canceled.
  case pairingCodeRejected

  /// Failed to generate or send the verification code.
  case verificationCodeFailed

  /// Attempt to save the authentication key in the keychain failed.
  case authenticationKeyStorageFailed

  /// Received a carId that doesn't conform to the required form.
  case malformedCarId

  /// The remote peer removed the pairing information causing connection failure.
  ///
  /// When the peripheral removes the classic bluetooth pairing with this phone, but the user has
  /// not removed the pairing on the phone, subsequent BLE connection attempts fail. The user must
  /// manually remove the bluetooth pairing with the peripheral via Settings -> Bluetooth and
  /// choosing to forget the peripheral.
  ///
  /// See: https://developer.apple.com/forums/thread/4732
  case peerRemovedPairingInfo
}
