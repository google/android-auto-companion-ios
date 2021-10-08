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

/// Possible operation types for a message.
public enum StreamOperationType {
  /// This message is meant to set up an encrypted channel.
  case encryptionHandshake

  /// This message is for a remote client.
  case clientMessage

  /// This message is a query to the remote client.
  case query

  /// This message is as response to a previous query.
  case queryResponse

  /// Converts this operation to its analogous `Com_Google_Companionprotos_OperationType`.
  ///
  /// - Returns: A `Com_Google_Companionprotos_OperationType`.
  func toOperationType() -> Com_Google_Companionprotos_OperationType {
    switch self {
    case .encryptionHandshake:
      return .encryptionHandshake
    case .clientMessage:
      return .clientMessage
    case .query:
      return .query
    case .queryResponse:
      return .queryResponse
    }
  }
}

/// Configuration parameters for a write of a message or contextual metadata for a received message.
public struct MessageStreamParams: Equatable {
  public let recipient: UUID
  public let operationType: StreamOperationType

  /// Creates a new parameter object.
  ///
  /// - Parameters:
  ///   - recipient: A unique identifier for a remote recipient that will receive the message.
  ///   - operationType: The operation type that this message represents.
  public init(recipient: UUID, operationType: StreamOperationType) {
    self.recipient = recipient
    self.operationType = operationType
  }
}
