// Copyright 2025 Google LLC
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

/// A connection error.
public enum ConnectionError: Error {
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
