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

@_implementationOnly import AndroidAutoSecureChannel
import Foundation

/// Possible errors thrown by this feature manager.
public enum FeatureManagerError: Error {
  /// Thrown when a message was attempted to be sent to a car that does not have a secure
  /// communication channel.
  case noSecureChannel
}

/// Base class for feature managers.
///
/// A feature manager is the entry point for a feature that requires a flow of data between the
/// current phone and car in order to function. This class abstracts away the boilerplate for
/// implementing a feature manager by registering the necessary observers for different car events,
/// such as when a car is ready for messages to be sent to it.
///
/// Each feature manager should have a unique UUID that identifies them. Ensure that the `featureID`
/// property is overridden, or this class will crash.
@available(watchOS 6.0, *)
@MainActor open class FeatureManager {
  private let connectedCarManager: ConnectedCarManager

  private var secureChannelHandle: ObservationHandle?
  private var connectHandle: ObservationHandle?
  private var disconnectHandle: ObservationHandle?
  private var dissociationHandle: ObservationHandle?

  private var messageReceivedHandles: [String: ObservationHandle] = [:]
  private var queryReceivedHandles: [String: ObservationHandle] = [:]

  /// An identifier that unique to this feature manager.
  ///
  /// This value must be overridden by subclasses or the class will crash.
  open var featureID: UUID {
    fatalError("Feature ID must be supplied.")
  }

  /// A list of cars that have secure communication channels established.
  ///
  /// The cars in this list can be sent secure messages.
  public final var securedCars: [Car] {
    return connectedCarManager.securedChannels.map { $0.car }
  }

  /// Initializes this feature manager by registering the necessary event observers on the given
  /// `ConnectedCarManager`.
  ///
  /// The `ConnectedCarManager` will provide the necessary APIs for feature managers to communicate
  /// with the car. It will never expose a car that has not been associated.
  ///
  /// - Parameter connectedCarManager: The manager of connecting cars.
  public init(connectedCarManager: ConnectedCarManager) {
    self.connectedCarManager = connectedCarManager

    connectHandle = connectedCarManager.observeConnection { [weak self] _, car in
      self?.onCarConnected(car)
    }

    dissociationHandle = connectedCarManager.observeDissociation { [weak self] _, car in
      self?.handleDisassociatedCar(car)
    }

    disconnectHandle = connectedCarManager.observeDisconnection { [weak self] _, car in
      self?.handleDisconnectedCar(car)
    }

    secureChannelHandle = connectedCarManager.observeSecureChannelSetUp { [weak self] _, channel in
      self?.handleSecureChannelEstablished(channel)
    }
  }

  deinit {
    secureChannelHandle?.cancel()
    connectHandle?.cancel()
    disconnectHandle?.cancel()
    dissociationHandle?.cancel()
    messageReceivedHandles.values.forEach { $0.cancel() }
    queryReceivedHandles.values.forEach { $0.cancel() }
  }

  // MARK: - Write methods.

  /// Sends the given message to the specified car if possible.
  ///
  /// If the given car is not currently connected, or a secure communication channel has not yet
  /// been set up, then this method will throw an error. Either keep track of this via the
  /// `onSecureChannelEstablished(for:)` callback or utilize the `isCarSecurelyConnected(_:)` before
  /// invoking this method.
  ///
  /// The optional `completion` parameter will be invoked with a value of `true` if the message was
  /// sent successfully.
  ///
  /// - Parameters:
  ///   - message: The message to send.
  ///   - car: The car to send to. If the given car is not securely connected, then this method will
  ///     throw an error
  ///   - completion: An optional completion block that will be invoked when a message has finished
  ///     sending.
  /// - Throws: An error if the given car is not set up for secure communication or an error occurs
  ///   during the message send.
  public final func sendMessage(
    _ message: Data,
    to car: Car,
    completion: ((Bool) -> Void)? = nil
  ) throws {
    guard let channel = connectedCarManager.securedChannel(for: car) else {
      throw FeatureManagerError.noSecureChannel
    }

    try channel.writeEncryptedMessage(message, to: featureID, completion: completion)
  }

  /// Sends a query to the given car.
  ///
  /// When the given car responds to the query, the given `response` closure will be invoked with
  /// the details of that response. The exact format of a query and response are feature defined.
  ///
  /// If the given car is not currently connected, or a secure communication channel has not yet
  /// been set up, then this method will throw an error. Either keep track of this via the
  /// `onSecureChannelEstablished(for:)` callback or utilize the `isCarSecurelyConnected(_:)` before
  /// invoking this method.
  ///
  /// - Parameters:
  ///   - query: The query to send to the car.
  ///   - car: The car that will receive the query. If the car is not securely connected, this
  ///     method will throw an error
  ///   - response: the closure that will be invoked when the car responds.
  /// - Throws: An error if the given car is not set up for secure communication or an error occurs
  ///   during the query.
  public final func sendQuery(
    _ query: Query,
    to car: Car,
    response: @escaping (QueryResponse) -> Void
  ) throws {
    guard let channel = connectedCarManager.securedChannel(for: car) else {
      throw FeatureManagerError.noSecureChannel
    }

    try channel.sendQuery(query, to: featureID, response: response)
  }

  /// Returns `true` if secure messages can be sent to the given car.
  public final func isCarSecurelyConnected(_ car: Car) -> Bool {
    return connectedCarManager.securedChannel(for: car) != nil
  }

  /// Returns a `FeatureSupportStatusProvider` for the given car.
  ///
  /// - Parameter car: The car for which to get the feature status provider.
  /// - Returns: `nil` if the car is not connected.
  func featureSupportStatusProvider(for car: Car) -> FeatureSupportStatusProvider? {
    return connectedCarManager.securedChannel(for: car)
  }

  // MARK: - Event methods.

  /// Invoked when a car has connected to this phone.
  ///
  /// A car being connected does not mean that secure messages can be sent to it. The
  /// `onSecureChannelEstablished(for:)` callback will be invoked when such messages can be sent.
  open func onCarConnected(_ car: Car) {}

  /// Invoked when a car has disconnected from this phone.
  open func onCarDisconnected(_ car: Car) {}

  /// Invoked when a secure communication channel has been established for the given car.
  ///
  /// Once this method has been called for a car, `sendMessage(to:)` can be called for that car.
  open func onSecureChannelEstablished(for car: Car) {}

  /// Invoked when a car has been disassociated.
  ///
  /// When a car has disassociated, it will need to undergo the association process again before
  /// secure messages can be sent. This event is a valid signal to clear any data that is linked to
  /// the given car.
  open func onCarDisassociated(_ car: Car) {}

  /// Invoked a message has been received from the indicated car.
  open func onMessageReceived(_ message: Data, from car: Car) {}

  /// Invoked when a query request has been received from the indicated car.
  ///
  /// To reply to the query, use the provided `responseHandle`. If the given car is not currently
  /// connected when the handle is invoked, then it will throw an error. Either keep track of this
  /// via the `onSecureChannelEstablished(for:)` callback or utilize the
  /// `isCarSecurelyConnected(_:)` before invoking the handle.
  ///
  /// - Parameters:
  ///   - query: The query from the car.
  ///   - car: The car that issued the query.
  ///   - responseHandle: A handle that should be used to respond to the given query.
  open func onQueryReceived(
    _ query: Query,
    from car: Car,
    responseHandle: QueryResponseHandle
  ) {}

  // MARK: - Private event methods.

  private func handleSecureChannelEstablished(_ channel: SecuredCarChannel) {
    initializeMessageObserver(on: channel)
    initializeQueryObserver(on: channel)
    onSecureChannelEstablished(for: channel.car)
  }

  private func handleDisconnectedCar(_ car: Car) {
    clearMessageHandles(for: car)
    onCarDisconnected(car)
  }

  private func handleDisassociatedCar(_ car: Car) {
    clearMessageHandles(for: car)
    onCarDisassociated(car)
  }

  private func initializeMessageObserver(on channel: SecuredCarChannel) {
    messageReceivedHandles[channel.car.id]?.cancel()

    do {
      let handle = try channel.observeMessageReceived(from: featureID) { [weak self] _, message in
        self?.onMessageReceived(message, from: channel.car)
      }

      messageReceivedHandles[channel.car.id] = handle
    } catch SecuredCarChannelError.observerAlreadyRegistered {
      fatalError(
        """
        Only one observer can be registered per feature. Another feature might be listening on \
        your messages. Double-check feature registration.
        """
      )
    } catch {
      // This error should not happen as only one error is thrown from the register
      // observer call.
      fatalError("An unexpected error occurred when registering a callback")
    }
  }

  private func initializeQueryObserver(on channel: SecuredCarChannel) {
    queryReceivedHandles[channel.car.id]?.cancel()

    do {
      let handle = try channel.observeQueryReceived(from: featureID) {
        [weak self] queryID, sender, query in
        self?.handleQuery(query, queryID: queryID, sender: sender, car: channel.car)
      }

      queryReceivedHandles[channel.car.id] = handle
    } catch SecuredCarChannelError.observerAlreadyRegistered {
      fatalError(
        """
        Only one query observer can be registered per feature. Another feature might be listening \
        on your messages. Double-check feature registration.
        """
      )
    } catch {
      // This error should not happen as only one error is thrown from the register
      // observer call.
      fatalError("An unexpected error occurred when registering a callback")
    }
  }

  private func handleQuery(_ query: Query, queryID: Int32, sender: UUID, car: Car) {
    // Construct a handle to abstract away the query ID from features. This closure will ensure
    // the right ID is passed to each response.
    let responseHandle = QueryResponseHandle { [weak self] response, isSuccessful in
      try self?.sendQueryResponse(
        QueryResponse(id: queryID, isSuccessful: isSuccessful, response: response),
        to: car,
        sender: sender
      )
    }
    onQueryReceived(query, from: car, responseHandle: responseHandle)
  }

  private func sendQueryResponse(
    _ queryResponse: QueryResponse, to car: Car, sender: UUID
  ) throws {
    guard let channel = connectedCarManager.securedChannel(for: car) else {
      throw FeatureManagerError.noSecureChannel
    }

    try channel.sendQueryResponse(queryResponse, to: sender)
  }

  private func clearMessageHandles(for car: Car) {
    messageReceivedHandles.removeValue(forKey: car.id)?.cancel()
    queryReceivedHandles.removeValue(forKey: car.id)?.cancel()
  }
}
