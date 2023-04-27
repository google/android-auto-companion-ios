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

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import Foundation

/// The possible errors that can result from sending an encrypted message to a car.
enum SecuredCarChannelError: Error {
  /// There was an error encrypting the message to send to the car.
  case cannotEncryptMessage

  /// This channel is currently in an invalid state and cannot be used to send messages.
  case invalidChannel

  /// An observer has already been registered for a given recipient. See `observeMessageReceived`
  /// for more detail.
  case observerAlreadyRegistered

  case invalidQueryResponse
}

/// A channel for a car that can be used to send encrypted messages.
@MainActor public protocol SecuredCarChannel: AnyObject, FeatureSupportStatusProvider {
  /// A car that messages are being sent to and from.
  var car: Car { get }

  /// The user's role with the car.
  ///
  /// A `nil` value means the IHU has not successfully responded with a user role.
  var userRole: UserRole? { get }

  /// Whether this secure channel is currently valid to send and receive messages through.
  var isValid: Bool { get }

  /// Observe when a message has been received from the given recipient.
  ///
  /// The closure passed to this method is passed the received message. Any messages that arrived
  /// before the registration of this observer will be delivered immediately following this call.
  ///
  /// Note: only one observer can be registered for each unique recipient. This is to prevent
  /// features from listening to messages that are not meant for it. If multiple observers are
  /// registered for the same recipient, then an error is thrown.
  ///
  /// - Parameters:
  ///   - recipient: A unique identifier for a recipient who sent the message.
  ///   - observation: A closure called when a message has been received.
  /// - Throws: An error if an observer has already been registered for the given `recipient`.
  func observeMessageReceived(
    from recipient: UUID,
    using observation: @escaping (SecuredCarChannel, Data) -> Void
  ) throws -> ObservationHandle

  /// Observe when a query has been received from the given recipient.
  ///
  /// The closure passed to this method is passed a unique identifier, the UUID of the sender and
  /// the details of the query. The sender UUID should be the UUID that a response is directed to.
  /// The unique identifier must be passed as part of `sendQueryResponse(_:)`. Any queries that
  /// arrived before the registration of this observer will be delivered immediately following this
  /// call.
  ///
  /// Note: only one observer can be registered for each unique recipient. This is to prevent
  /// features from listening to messages that are not meant for it. If multiple observers are
  /// registered for the same recipient, then an error is thrown.
  ///
  /// - Parameters:
  ///   - recipient: A unique identifier for a recipient who sent the query.
  ///   - observation: A closure called when a query has been received.
  /// - Returns: A handle that that can be used to cancel an observation
  /// - Throws: An error if an observer has already been registered for the given `recipient`.
  func observeQueryReceived(
    from recipient: UUID,
    using observation: @escaping ((Int32, UUID, Query) -> Void)
  ) throws -> ObservationHandle

  /// Writes an encrypted message to the recipient on the car associated with this class.
  ///
  /// Upon completion, the passed closure is passed a boolean of `true` if successful.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - recipient: The unique identifier for a recipient that will receive the message.
  ///   - completion: The handler to be called on write completion or `nil` if there is no
  ///   need to be notified of a successful message write.
  /// - Throws: An error if the message to send cannot be encrypted or this channel is not currently
  ///   valid to send message.
  // Note: No @escaping needed on `completion` because an optional type implicitly escapes.
  func writeEncryptedMessage(
    _ message: Data,
    to recipient: UUID,
    completion: ((Bool) -> Void)?
  ) throws

  /// Sends a query request to the recipient on the car associated with this class.
  ///
  /// The recipient will respond via the `response` closure that is passed to this method. The
  /// closure will be passed a boolean indicating if the query was successful and a `Data` object
  /// representing the response. The format of the `Query` data and response data are decided by
  /// the feature issuing the query.
  ///
  /// - Parameters:
  ///   - query: The query to send.
  ///   - recipient: The unique identifier for a recipient that will receive the message.
  ///   - response: The closure to be called when the recipient has responded to the query.
  /// - Throws: An error if the query cannot be sent correctly.
  func sendQuery(
    _ query: Query,
    to recipient: UUID,
    response: @escaping ((QueryResponse) -> Void)
  ) throws

  /// Sends a query request to the recipient on the car associated with this class.
  ///
  /// The recipient will respond via the `response` closure that is passed to this method. The
  /// closure will be passed a boolean indicating if the query was successful and a `Data` object
  /// representing the response. The format of the `Query` data and response data are decided by
  /// the feature issuing the query.
  ///
  /// - Parameters:
  ///   - query: The query to send.
  ///   - recipient: The unique identifier for a recipient that will receive the message.
  /// - Throws: An error if the query cannot be sent correctly.
  func sendQuery(
    _ query: Query,
    to recipient: UUID
  ) async throws -> QueryResponse

  /// Sends a response to a query.
  ///
  /// The `queryResponse` has an ID field that should match the ID given via the closure passed
  /// to `observeQueryReceived`.
  ///
  /// - Parameters:
  ///   - queryResponse: The response to send.
  ///   - recipient: The unique identifier for a recipient that will receive the response.
  /// - Throws: An error if the query response could not be sent.
  func sendQueryResponse(_ queryResponse: QueryResponse, to recipient: UUID) throws
}

extension SecuredCarChannel {
  public func sendQuery(
    _ query: Query,
    to recipient: UUID
  ) async throws -> QueryResponse {
    return try await withUnsafeThrowingContinuation { continuation in
      do {
        try sendQuery(query, to: recipient) { queryResponse in
          continuation.resume(returning: queryResponse)
        }
      } catch {
        continuation.resume(throwing: error)
      }
    }
  }
}
