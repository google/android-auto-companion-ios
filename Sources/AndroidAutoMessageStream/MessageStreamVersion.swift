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

/// The different types of message streams that are available to be created.
public enum MessageStreamVersion: Equatable {
  /// A message stream that will simply pass given messages to and from a peripheral back
  /// to the caller without any special handling.
  case passthrough

  /// A message stream that uses version 2 of the messaging protobuf and optionally compression.
  /// Pass `true` if compression is allowed.
  case v2(Bool)
}

/// The supported message security versions.
///
/// See go/aae-batmobile-versioning for details.
public enum MessageSecurityVersion: Int32 {
  /// Device IDs are exchanged during association before encryption. The head unit advertises the
  /// device ID as the service UUID for reconnection.
  case v1 = 1

  /// Device IDs are exchanged during association after encryption. The head unit advertises a
  /// fixed service UUID for reconnection. See go/aae-batmobile-hide-device-ids for details.
  case v2 = 2

  /// Capabilities are exchanged during association after version resolution. This implementation
  /// just provides for empty capabilities as this version is being deprecated in favor of V4.
  /// Device IDs are exchanged during association after encryption. The head unit advertises a
  /// fixed service UUID for reconnection. See go/aae-batmobile-hide-device-ids for details.
  case v3 = 3

  /// This version allows for the remote device to provide an out of band token that can be used
  /// to validate the UKey2 verification code exchanged during association. If the token is present
  /// it will be used to verify the remote device and skip the visual pairing code confirmation. If
  /// the token is not present, the user will be presented with the pairing code for visual
  /// confirmation on the remote device.
  ///
  /// This device must send a `VerificationCodeState` to the remote device indicating how
  /// the verification will be performed (visual or OOB token).
  ///
  /// Device IDs are exchanged during association after encryption. The head unit advertises a
  /// fixed service UUID for reconnection. See go/aae-batmobile-hide-device-ids for details.
  case v4 = 4
}
