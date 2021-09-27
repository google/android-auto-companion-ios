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
import AndroidAutoCompanionProtos

/// Convenience extensions for `Aae_Blemessagestream_OperationType`.
extension Com_Google_Companionprotos_OperationType {
  /// Returns an analogous `StreamOperationType` for this operation.
  ///
  /// - Returns: A `StreamOperationType`.
  func toStreamOperationType() -> StreamOperationType {
    switch self {
    case .encryptionHandshake:
      return .encryptionHandshake
    case .query:
      return .query
    case .queryResponse:
      return .queryResponse
    default:
      // Note: defaulting to `clientMessage` for all OperationTypes because the details of the
      // other operations should not be exposed to clients. For example, the operation type of
      // ACK should be processed internally.
      return .clientMessage
    }
  }
}
