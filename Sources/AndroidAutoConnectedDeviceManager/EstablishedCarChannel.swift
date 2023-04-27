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

@_implementationOnly import AndroidAutoConnectedDeviceTransport
@_implementationOnly import AndroidAutoCoreBluetoothProtocols
import AndroidAutoLogger
@_implementationOnly import AndroidAutoMessageStream
import Foundation
@_implementationOnly import AndroidAutoCompanionProtos

private typealias QueryProto = Com_Google_Companionprotos_Query
private typealias QueryResponseProto = Com_Google_Companionprotos_QueryResponse

/// A car that can be used to send encrypted messages.
@MainActor class EstablishedCarChannel: NSObject, SecuredCarChannelPeripheral {
  private static let log = Logger(for: EstablishedCarChannel.self)

  let messageStream: MessageStream
  private let connectionHandle: ConnectionHandle

  private var writeCompletionHandlers: [@MainActor (Bool) -> Void] = []
  private var receivedMessageObservations: [UUID: (EstablishedCarChannel, Data) -> Void] = [:]

  /// Keeps track of unique recipient UUIDs that are being observed and the observations that are
  /// listening for them.
  ///
  /// The key in this map is the recipient UUID and the value is the observation UUID.
  private var messageRecipientToObservations: [UUID: UUID] = [:]

  /// Messages that were received, but had no registered observation for them.
  ///
  /// These messages are saved until an observer is registered, after which the messages are sent to
  /// that observation in the order they are received.
  private var missedMessagesForRecipients: [UUID: [Data]] = [:]

  /// A mapping of feature IDs to closures that should be notified when a query is received for that
  /// feature.
  private var receivedQueryObservations: [UUID: (Int32, UUID, Query) -> Void] = [:]

  /// Queries that were received, but had no registered observation for them.
  ///
  /// These queries are saved until an observer is registered, after which the queries are sent to
  /// that observation in the order they are received.
  private var missedQueriesForRecipients: [UUID: [(Int32, UUID, Query)]] = [:]

  /// Keep track of unique recipient UUIDs being observed to an identifier for observations
  /// that should be invoked when a query is received.
  ///
  /// The key in this map is the recipient UUID and the value is the observation UUID.
  private var queryRecipientToObservations: [UUID: UUID] = [:]

  /// A map of query IDs to responders that should be invoked when a response to the query has come
  /// back.
  private var queryResponseHandlers: [Int32: ((QueryResponse) -> Void)] = [:]

  /// The current ID to use for queries.
  ///
  /// This value should always be non-negative and is defined as an `Int32` because it needs to be
  /// set on a proto. Utilize the `nextQueryID()` method to retrieve the value that should be set on
  /// this proto.
  var queryID: Int32 = 0

  public let car: Car
  public private(set) var userRole: UserRole?

  var peripheral: AnyTransportPeripheral {
    return messageStream.peripheral
  }

  public var isValid: Bool {
    return messageStream.peripheral.isConnected && messageStream.isValid
  }

  /// Initializes this channel with a stream that already has encryption established and is
  /// immediately ready to send messages.
  ///
  /// - Parameters:
  ///   - car: The car that associated with the messageStream
  ///   - connectionHandle: A handle for managing connections to remote cars.
  ///   - messageStream: An established stream that will handle sending of messages.
  init(
    car: Car,
    connectionHandle: ConnectionHandle,
    messageStream: MessageStream
  ) {
    self.car = car
    self.connectionHandle = connectionHandle
    self.messageStream = messageStream

    // `init()` needs to be called before `self` can be used for purposes other than referencing
    // fields.
    super.init()
    messageStream.delegate = self
  }
}

// MARK: - SecuredCarChannel

extension EstablishedCarChannel: SecuredCarChannel {
  public func observeMessageReceived(
    from recipient: UUID,
    using observation: @escaping (SecuredCarChannel, Data) -> Void
  ) throws -> ObservationHandle {
    guard messageRecipientToObservations[recipient] == nil else {
      throw SecuredCarChannelError.observerAlreadyRegistered
    }

    let id = UUID()
    receivedMessageObservations[id] = observation
    messageRecipientToObservations[recipient] = id

    // Check for missed messages after the handle has been returned. This allows observers to not
    // have to worry about race conditions between registering and receiving messages.
    defer {
      if let missedMessages = missedMessagesForRecipients[recipient] {
        for message in missedMessages {
          observation(self, message)
        }
        missedMessagesForRecipients[recipient] = nil
      }
    }

    return ObservationHandle { [weak self] in
      self?.receivedMessageObservations.removeValue(forKey: id)
      self?.messageRecipientToObservations[recipient] = nil
    }
  }

  func observeQueryReceived(
    from recipient: UUID,
    using observation: @escaping ((Int32, UUID, Query) -> Void)
  ) throws -> ObservationHandle {
    guard queryRecipientToObservations[recipient] == nil else {
      throw SecuredCarChannelError.observerAlreadyRegistered
    }

    let id = UUID()
    receivedQueryObservations[id] = observation
    queryRecipientToObservations[recipient] = id

    // Check for missed queries after the handle has been returned. This allows observers to not
    // have to worry about race conditions between registering and receiving queries.
    defer {
      if let missedQueries = missedQueriesForRecipients[recipient] {
        for (id, sender, query) in missedQueries {
          observation(id, sender, query)
        }
        missedQueriesForRecipients[recipient] = nil
      }
    }

    return ObservationHandle { [weak self] in
      self?.receivedQueryObservations.removeValue(forKey: id)
      self?.queryRecipientToObservations[recipient] = nil
    }
  }

  public func writeEncryptedMessage(
    _ message: Data,
    to recipient: UUID,
    completion: ((Bool) -> Void)?
  ) throws {
    guard isValid else {
      throw SecuredCarChannelError.invalidChannel
    }

    do {
      try messageStream.writeEncryptedMessage(
        message,
        params: MessageStreamParams(recipient: recipient, operationType: .clientMessage)
      )

      // Ensure that there is always a completion handler for each write. This simplifies the logic
      // of notifying handlers when a write is complete because a closure can always be called.
      writeCompletionHandlers.append(completion ?? noop)
    } catch {
      Self.log.error("Attempt to write encrypted message failed: \(error.localizedDescription)")

      throw SecuredCarChannelError.cannotEncryptMessage
    }
  }

  func sendQuery(
    _ query: Query,
    to recipient: UUID,
    response: @escaping ((QueryResponse) -> Void)
  ) throws {
    guard isValid else {
      throw SecuredCarChannelError.invalidChannel
    }

    let queryID = nextQueryID()
    do {
      try messageStream.writeEncryptedMessage(
        try query.toProtoData(queryID: queryID, sender: recipient),
        params: MessageStreamParams(recipient: recipient, operationType: .query)
      )

      // Add a no-op completion handler to be called when the query has finished sending. This
      // ensures all out-standing messages have completion handlers.
      writeCompletionHandlers.append(noop)
      queryResponseHandlers[queryID] = response
    } catch {
      Self.log.error("Attempt to send query failed: \(error.localizedDescription)")
      throw SecuredCarChannelError.cannotEncryptMessage
    }
  }

  func sendQueryResponse(_ queryResponse: QueryResponse, to recipient: UUID) throws {
    guard isValid else {
      throw SecuredCarChannelError.invalidChannel
    }

    do {
      try messageStream.writeEncryptedMessage(
        try queryResponse.toProtoData(),
        params: MessageStreamParams(recipient: recipient, operationType: .queryResponse)
      )

      // Add a no-op completion handler to be called when the response has finished sending. This
      // ensures all out-standing messages have completion handlers.
      writeCompletionHandlers.append(noop)
    } catch {
      Self.log.error("Attempt to send query response failed: \(error.localizedDescription)")
      throw SecuredCarChannelError.cannotEncryptMessage
    }
  }

  /// Returns the ID to use for a new query.
  private func nextQueryID() -> Int32 {
    let currentQueryID = queryID

    if queryID == Int32.max {
      // The ID cannot be negative, so reset to 0.
      queryID = 0
    } else {
      queryID += 1
    }

    return currentQueryID
  }

  /// Convenience method that performs no action.
  private func noop(_ value: Bool) {}

  func isFeatureSupported(_ featureID: UUID) -> Bool {
    return messageRecipientToObservations[featureID] != nil
  }
}

// MARK: - SecuredConnectedDeviceChannel
extension EstablishedCarChannel: SecuredConnectedDeviceChannel {
  public func configure(
    using provider: ChannelFeatureProvider,
    completion: @escaping (SecuredConnectedDeviceChannel) -> Void
  ) {
    provider.requestUserRole(with: self) { [weak self] role in
      guard let self = self else { return }

      defer { completion(self) }
      if let role = role {
        Self.log.info("requestUserRole completed with role: \(role)")
        self.userRole = role
      } else {
        Self.log.error("requestUserRole failed with no role.")
      }
    }
  }
}

// MARK: - MessageStreamDelegate

extension EstablishedCarChannel: MessageStreamDelegate {
  public func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {
    Self.log.error(
      """
      Encountered error when writing to stream. \
      \(messageStream.writingDebugDescription): \
      \(error.localizedDescription)
      """
    )

    // This should not happen because a handler is always stored for every write.
    guard !writeCompletionHandlers.isEmpty else {
      assertionFailure("No completion handler to call after a message write failure.")

      Self.log.fault(
        "Unexpected. No completion handler able to call after a message write failure.")
      return
    }

    let handler = writeCompletionHandlers.removeFirst()
    handler(false)
  }

  public func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {
    switch params.operationType {
    case .clientMessage:
      handleClientMessage(message, from: params.recipient)
    case .queryResponse:
      Self.log.debug("Received query response for recipient with UUID \(params.recipient)")
      handleQueryResponse(message)
    case .query:
      Self.log.debug("Received query for recipient with UUID \(params.recipient)")
      handleQuery(message, for: params.recipient)
    default:
      Self.log.error(
        "Received message of unexpected operation type: \(params.operationType). Ignoring")
    }
  }

  private func handleClientMessage(_ message: Data, from recipient: UUID) {
    if let observationUUID = messageRecipientToObservations[recipient] {
      Self.log.debug("Received client message. Passing onto feature with UUID \(recipient)")

      receivedMessageObservations[observationUUID]?(self, message)
      return
    }

    Self.log(
      "Received client message for \(recipient), but no registered observer. Saving message.")

    if missedMessagesForRecipients[recipient] == nil {
      missedMessagesForRecipients[recipient] = []
    }

    missedMessagesForRecipients[recipient]?.append(message)
  }

  private func handleQueryResponse(_ message: Data) {
    guard let query = try? QueryResponseProto(serializedData: message) else {
      Self.log.error("Received query response but unable to parse. Ignoring.")
      return
    }

    guard let responseHandler = queryResponseHandlers.removeValue(forKey: query.queryID) else {
      Self.log.error(
        """
        Unexpected. Received query response with id \(query.queryID), \
        but no callback registered. Ignoring.
        """
      )
      return
    }

    responseHandler(query.toQueryResponse())
  }

  private func handleQuery(_ message: Data, for recipient: UUID) {
    guard let query = try? QueryProto(serializedData: message) else {
      Self.log.error("Received query but unable to parse. Ignoring.")
      return
    }

    if let observationID = queryRecipientToObservations[recipient] {
      // Unlikely for this unwrap to fail since the observation ID is created at the time of
      // registration.
      receivedQueryObservations[observationID]?(query.id, query.senderUUID, query.toQuery())
      return
    }

    Self.log.error(
      "Received query for recipient \(recipient) but no registered observation. Saving query")

    if missedQueriesForRecipients[recipient] == nil {
      missedQueriesForRecipients[recipient] = []
    }

    missedQueriesForRecipients[recipient]?.append((query.id, query.senderUUID, query.toQuery()))
  }

  public func messageStreamDidWriteMessage(
    _ messageStream: MessageStream,
    to recipient: UUID
  ) {
    // This should not happen because a handler is always stored for every write.
    guard !writeCompletionHandlers.isEmpty else {
      assertionFailure("No completion handler to call after a successful message write.")

      Self.log.fault(
        "Unexpected. No completion handler able to call after a successful message write.")
      return
    }

    let handler = writeCompletionHandlers.removeFirst()
    handler(true)
  }

  public func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {
    Self.log.error("Underlying BLEMessageStream encountered unrecoverable error. Disconnecting.")
    connectionHandle.disconnect(messageStream)
  }
}

// MARK: - Helper extensions

extension QueryProto {
  /// Converts this proto to its `Query` representation.
  fileprivate func toQuery() -> Query {
    return Query(request: self.request, parameters: self.parameters)
  }

  /// A `UUID` representation of the `sender` field.
  fileprivate var senderUUID: UUID {
    NSUUID(uuidBytes: [UInt8](self.sender)) as UUID
  }

}

extension QueryResponseProto {
  /// Converts this proto to its `QueryResponse` representation
  fileprivate func toQueryResponse() -> QueryResponse {
    return QueryResponse(id: self.queryID, isSuccessful: self.success, response: self.response)
  }
}
