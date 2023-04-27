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

import AndroidAutoConnectedDeviceManagerMocks
import AndroidAutoSecureChannel
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// An `enum` to hold constants specific to this test.
private enum Constants {
  // The values of these UUIDs are arbitrary; they just need to be different.
  static let featureID = UUID(uuidString: "8ed7346c-0a15-414f-af26-2964f7b17570")!
  static let differentID = UUID(uuidString: "7e796761-2422-4552-bb0d-97bb3fc1bcfa")!
  static let senderId = UUID(uuidString: "0497aec5-cd44-4f31-ae92-5d3356159aea")!
}

/// Unit tests for `FeatureManager`.
@available(watchOS 6.0, *)
@MainActor class FeatureManagerTest: XCTestCase {
  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var featureManager: ObservableFeatureManager!

  override func setUp() async throws {
    try await super.setUp()

    continueAfterFailure = false

    connectedCarManagerMock = ConnectedCarManagerMock()
    featureManager = ObservableFeatureManager(connectedCarManager: connectedCarManagerMock)
  }

  // MARK: - Event method assertions.

  func testCarConnected_invokesOnCarConnected() {
    let car = Car(id: "id", name: "name")
    connectedCarManagerMock.triggerConnection(for: car)

    XCTAssertEqual(featureManager.onCarConnectedCalledCount, 1)
    XCTAssertEqual(featureManager.connectedCars[0], car)
  }

  func testCarDisconnected_invokesOnCarDisconnected() {
    let car = Car(id: "id", name: "name")
    connectedCarManagerMock.triggerDisconnection(for: car)

    XCTAssertEqual(featureManager.onCarDisconnectedCalledCount, 1)
    XCTAssertEqual(featureManager.disconnectedCars[0], car)
  }

  func testSecureChannelEstablished_invokesOnSecureChannelEstablished() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertEqual(featureManager.onSecureChannelEstablishedCalledCount, 1)
    XCTAssertEqual(featureManager.carsWithSecuredChannels[0], car)
  }

  func testCarDisassociated_invokesOnCarDisassociated() {
    let car = Car(id: "id", name: "name")
    connectedCarManagerMock.triggerDissociation(for: car)

    XCTAssertEqual(featureManager.onCarDisassociatedCalledCount, 1)
    XCTAssertEqual(featureManager.disassociatedCars[0], car)
  }

  // MARK: - Message received tests.

  func testOnMessageReceived_invokesCallback() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let message = Data("message".utf8)
    channel.triggerMessageReceived(message, from: Constants.featureID)

    XCTAssertEqual(featureManager.receivedMessages.count, 1)
    XCTAssertEqual(featureManager.receivedMessages[0], message)
    XCTAssertEqual(featureManager.carsWithReceivedMessages[0], car)
  }

  func testOnMessageReceived_fromDifferentRecipient_doesNotInvokeCallback() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let message = Data("message".utf8)
    let wrongRecipient = Constants.differentID
    channel.triggerMessageReceived(message, from: wrongRecipient)

    XCTAssertTrue(featureManager.receivedMessages.isEmpty)
  }

  func testOnMessageReceived_afterDisconnection_doesNotInvokeCallback() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    connectedCarManagerMock.triggerDisconnection(for: car)

    let message = Data("message".utf8)
    channel.triggerMessageReceived(message, from: Constants.featureID)

    XCTAssertTrue(featureManager.receivedMessages.isEmpty)
  }

  func testOnMessageReceived_afterDisassociation_doesNotInvokeCallback() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    connectedCarManagerMock.triggerDissociation(for: car)

    let message = Data("message".utf8)
    channel.triggerMessageReceived(message, from: Constants.featureID)

    XCTAssertTrue(featureManager.receivedMessages.isEmpty)
  }

  // MARK: - Send message tests.

  func testSendMessage_writesToSecureChannel() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let message = Data("message".utf8)
    XCTAssertNoThrow(try featureManager.sendMessage(message, to: car))

    XCTAssertEqual(channel.writtenMessages.count, 1)
    XCTAssertEqual(channel.writtenMessages[0], message)
  }

  func testSendMessage_toNotSecuredCar_throwsError() {
    let car = Car(id: "id", name: "name")
    let message = Data("message".utf8)

    // Calling send message without triggering a secure channel set up first.
    XCTAssertThrowsError(
      try featureManager.sendMessage(message, to: car)
    ) { error in
      XCTAssertEqual(error as! FeatureManagerError, .noSecureChannel)
    }
  }

  func testSendMessage_channelWriteError_throwsError() {
    let car = Car(id: "id", name: "name")

    // An invalid channel will fail when `writeEncryptedMessage` is called.
    let channel = SecuredCarChannelMock(car: car)
    channel.isValid = false

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let message = Data("message".utf8)
    XCTAssertThrowsError(try featureManager.sendMessage(message, to: car))
  }

  // MARK: - isCarSecurelyConnected tests.

  func testIsCarSecurelyConnected_returnsTrueIfChannelExists() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(featureManager.isCarSecurelyConnected(car))
  }

  func testIsCarSecurelyConnected_returnsFalseIfNoChannel() {
    let car = Car(id: "id", name: "name")
    XCTAssertFalse(featureManager.isCarSecurelyConnected(car))
  }

  // MARK: - Send query tests.

  func testSendQuery_writesToSecureChannel() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let query = Query(request: Data("request".utf8), parameters: nil)
    XCTAssertNoThrow(try featureManager.sendQuery(query, to: car, response: { _ in }))

    XCTAssertEqual(channel.writtenQueries.count, 1)
    XCTAssertEqual(channel.writtenQueries[0], query)
  }

  func testSendQuery_toNotSecuredCar_throwsError() {
    let car = Car(id: "id", name: "name")
    let query = Query(request: Data("request".utf8), parameters: nil)

    // Calling send message without triggering a secure channel set up first.
    XCTAssertThrowsError(
      try featureManager.sendQuery(query, to: car, response: { _ in })
    ) { error in
      XCTAssertEqual(error as! FeatureManagerError, .noSecureChannel)
    }
  }

  func testSendQuery_channelWriteError_throwsError() {
    let car = Car(id: "id", name: "name")

    // An invalid channel will fail when `writeEncryptedMessage` is called.
    let channel = SecuredCarChannelMock(car: car)
    channel.isValid = false

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let query = Query(request: Data("request".utf8), parameters: nil)
    XCTAssertThrowsError(try featureManager.sendQuery(query, to: car, response: { _ in }))
  }

  // MARK: - Query response received tests

  func testQueryResponseReceived_notifiesIfQuerySent() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let query = Query(request: Data("request".utf8), parameters: nil)

    let queryID: Int32 = 5
    channel.queryID = queryID

    let responseCalled = expectation(description: "Response called")
    let expectedQueryResponse =
      QueryResponse(id: queryID, isSuccessful: true, response: Data("response".utf8))

    XCTAssertNoThrow(
      try featureManager.sendQuery(query, to: car) { queryResponse in
        responseCalled.fulfill()
        XCTAssertEqual(queryResponse, expectedQueryResponse)
      })

    channel.triggerQueryResponse(expectedQueryResponse)

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Response was not called")
      }
    }
  }

  func testQueryResponseReceived_doesNotNotify_ifNoCorrespondingQuery() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let query = Query(request: Data("request".utf8), parameters: nil)

    let queryID: Int32 = 5
    let otherQueryID: Int32 = 10
    channel.queryID = otherQueryID

    let responseNotCalled = expectation(description: "Response called")
    responseNotCalled.isInverted = true

    let expectedQueryResponse =
      QueryResponse(id: queryID, isSuccessful: true, response: Data("response".utf8))

    XCTAssertNoThrow(
      try featureManager.sendQuery(query, to: car) { _ in
        responseNotCalled.fulfill()
      })

    channel.triggerQueryResponse(expectedQueryResponse)

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Response was called")
      }
    }
  }

  // MARK: - On query received tests

  func testOnQueryReceived_notifiesForIncomingQuery() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let query = Query(request: Data("request".utf8), parameters: Data())
    channel.triggerQuery(
      query, queryID: 5, sender: Constants.senderId, recipient: Constants.featureID)

    XCTAssertEqual(featureManager.receivedQueries.count, 1)
    XCTAssertEqual(featureManager.receivedQueries[0], query)

    XCTAssertEqual(featureManager.carsWithReceivedQueries.count, 1)
    XCTAssertEqual(featureManager.carsWithReceivedQueries[0], car)
  }

  func testOnQueryReceived_responseHandle_writesToSecureChannel() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let queryID: Int32 = 5
    let query = Query(request: Data("request".utf8), parameters: Data())
    channel.triggerQuery(
      query, queryID: queryID, sender: Constants.senderId, recipient: Constants.featureID)

    XCTAssertEqual(featureManager.queryResponseHandlers.count, 1)
    let responseHandle = featureManager.queryResponseHandlers[0]

    let response = Data("response".utf8)
    XCTAssertNoThrow(try responseHandle.respond(with: response, isSuccessful: true))

    let expectedQueryResponse =
      QueryResponse(id: queryID, isSuccessful: true, response: response)

    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
    XCTAssertEqual(channel.writtenQueryResponses[0].recipient, Constants.senderId)
  }

  // MARK: feature support status provider tests

  func testFeatureSupportStatusProvider_connectedCar_returnsProvider() {
    let car = Car(id: "id", name: "name")
    let channel = SecuredCarChannelMock(car: car)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertNotNil(featureManager.featureSupportStatusProvider(for: car))
  }

  func testFeatureSupportStatusProvider_unconnectedCar_returnsNilProvider() {
    let car = Car(id: "id", name: "name")

    XCTAssertNil(featureManager.featureSupportStatusProvider(for: car))
  }
}

/// A `FeatureManager` implementation that allows for assertions on its event methods.
@available(watchOS 6.0, *)
private class ObservableFeatureManager: FeatureManager {
  override var featureID: UUID {
    return Constants.featureID
  }

  var onCarConnectedCalledCount = 0
  var connectedCars = [Car]()

  var onCarDisconnectedCalledCount = 0
  var disconnectedCars = [Car]()

  var onSecureChannelEstablishedCalledCount = 0
  var carsWithSecuredChannels = [Car]()

  var onCarDisassociatedCalledCount = 0
  var disassociatedCars = [Car]()

  var receivedMessages = [Data]()
  var carsWithReceivedMessages = [Car]()

  var receivedQueries = [Query]()
  var carsWithReceivedQueries = [Car]()
  var queryResponseHandlers = [QueryResponseHandle]()

  override func onCarConnected(_ car: Car) {
    onCarConnectedCalledCount += 1
    connectedCars.append(car)
  }

  override func onCarDisconnected(_ car: Car) {
    onCarDisconnectedCalledCount += 1
    disconnectedCars.append(car)
  }

  override func onSecureChannelEstablished(for car: Car) {
    onSecureChannelEstablishedCalledCount += 1
    carsWithSecuredChannels.append(car)
  }

  override func onCarDisassociated(_ car: Car) {
    onCarDisassociatedCalledCount += 1
    disassociatedCars.append(car)
  }

  override func onMessageReceived(_ message: Data, from car: Car) {
    receivedMessages.append(message)
    carsWithReceivedMessages.append(car)
  }

  override func onQueryReceived(
    _ query: Query,
    from car: Car,
    responseHandle: QueryResponseHandle
  ) {
    receivedQueries.append(query)
    carsWithReceivedQueries.append(car)
    queryResponseHandlers.append(responseHandle)
  }
}
