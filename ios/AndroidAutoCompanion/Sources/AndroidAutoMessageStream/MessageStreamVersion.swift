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
public enum BLEMessageSecurityVersion: Int32 {
  /// Device IDs are exchanged during association before encryption. The head unit advertises the
  /// device ID as the service UUID for reconnection.
  case v1 = 1

  /// Device IDs are exchanged during association after encryption. The head unit advertises a
  /// fixed service UUID for reconnection. See go/aae-batmobile-hide-device-ids for details.
  case v2 = 2
}
