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
import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import AndroidAutoMessageStream
import CoreBluetooth
import XCTest

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `EstablishedCarChannel`.
@MainActor class EstablishedCarChannelTest: XCTestCase {
  private let carId = "carId"
  private let car = PeripheralMock(name: "carName")
  private let savedSession = SecureBLEChannelMock.mockSavedSession

  private var messageStream: BLEMessageStreamFake!
  private var channel: EstablishedCarChannel!
  private var connectionHandle: ConnectionHandleFake!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    car.reset()

    messageStream = BLEMessageStreamFake(peripheral: car)
    connectionHandle = ConnectionHandleFake()

    channel = EstablishedCarChannel(
      car: Car(id: carId, name: "mock"),
      connectionHandle: connectionHandle,
      messageStream: messageStream
    )
  }

  func testPeripheral_matchesBLEMessageStreamPeripheral() {
    XCTAssert(channel.peripheral === messageStream.peripheral)
  }

  func testBleMessagestream_encountersError_disconnects() {
    channel.messageStreamEncounteredUnrecoverableError(messageStream)
    XCTAssertTrue(connectionHandle.disconnectCalled)
    XCTAssert(connectionHandle.disconnectedStream === messageStream)
  }

  // MARK: - Write messages tests.

  func testWriteMessage_writesToStream() {
    let message = Data("message".utf8)

    XCTAssertNoThrow(
      try channel.writeEncryptedMessage(message, to: UUID(), completion: nil))

    XCTAssertEqual(messageStream.writtenEncryptedMessages.count, 1)
    XCTAssertEqual(messageStream.writtenEncryptedMessages[0].message, message)
  }

  func testWriteMessage_throwsErrorIfInvalid() {
    // Simulate the car disconnecting.
    car.state = .disconnected

    let recipient = UUID()
    let message = Data("message".utf8)
    XCTAssertThrowsError(
      try channel.writeEncryptedMessage(message, to: recipient) { success in
        XCTFail("Completion handler should not be called.")
      }
    ) { error in
      XCTAssertEqual(error as! SecuredCarChannelError, .invalidChannel)
    }
  }

  func testWriteMessage_fails_notifiesCompletionHandler() {
    let handlerCalledExpectation = expectation(description: "Completion handler called.")

    // Clear any messages that were written to the car to make subsequent assertions easier.
    car.reset()

    let recipient = UUID()
    let message = Data("message".utf8)
    try! channel.writeEncryptedMessage(message, to: recipient) { success in
      // Message write should have failed.
      XCTAssertFalse(success)
      handlerCalledExpectation.fulfill()
    }

    // Notify that the write failed.
    messageStream.triggerWriteError(to: recipient)

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testWriteMessage_succeeds_notifiesCompletionHandler() {
    let handlerCalledExpectation = expectation(description: "Completion handler called.")

    // Clear any messages that were written to the car to make subsequent assertions easier.
    car.reset()

    let recipient = UUID()
    let message = Data("message".utf8)
    try! channel.writeEncryptedMessage(message, to: recipient) { success in
      // Message should have written successfully.
      XCTAssertTrue(success)
      handlerCalledExpectation.fulfill()
    }

    // Notify that the write was successful.
    channel.messageStreamDidWriteMessage(messageStream, to: recipient)

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  // MARK: - Received message tests.

  func testReceivedMessage_ignoresUnknownOperationType() {
    let receivedMessage = Data("Received message".utf8)
    let handlerNotCalledExpectation = expectation(description: "Completion handler called.")
    handlerNotCalledExpectation.isInverted = true

    let recipient = UUID()
    let _ = try! channel.observeMessageReceived(from: recipient) { _, message in
      XCTAssertEqual(message, receivedMessage)
      handlerNotCalledExpectation.fulfill()
    }

    // Simulate the car sending a message with incorrect operation type.
    messageStream.triggerMessageReceived(
      receivedMessage,
      params: MessageStreamParams(
        recipient: recipient,
        operationType: .encryptionHandshake
      )
    )

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testReceivedMessage_notifiesObserversWithMessage() {
    let receivedMessage = Data("Received message".utf8)
    let handlerCalledExpectation = expectation(description: "Completion handler called.")

    let recipient = UUID()
    let _ = try! channel.observeMessageReceived(from: recipient) { _, message in
      XCTAssertEqual(message, receivedMessage)
      handlerCalledExpectation.fulfill()
    }

    // Simulate the car sending a message.
    messageStream.triggerMessageReceived(
      receivedMessage,
      params: MessageStreamParams(
        recipient: recipient,
        operationType: .clientMessage
      )
    )

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testObserveReceivedMessage_deliversMissedMessages() {
    let receivedMessage = Data("Received message".utf8)
    let handlerCalledExpectation = expectation(description: "Completion handler called.")
    let recipient = UUID()

    // Simulate the car sending a message before message registration.
    messageStream.triggerMessageReceived(
      receivedMessage,
      params: MessageStreamParams(
        recipient: recipient,
        operationType: .clientMessage
      )
    )

    // Now register an observer.
    let _ = try! channel.observeMessageReceived(from: recipient) { _, message in
      XCTAssertEqual(message, receivedMessage)
      handlerCalledExpectation.fulfill()
    }

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testObserveReceivedMessage_deliversMissedMessages_onlyOnce() {
    let receivedMessage = Data("Received message".utf8)
    let handlerNotCalledExpectation = expectation(description: "Completion handler called.")
    handlerNotCalledExpectation.isInverted = true
    let recipient = UUID()

    // Simulate the car sending a message before message registration.
    messageStream.triggerMessageReceived(
      receivedMessage,
      params: MessageStreamParams(
        recipient: recipient,
        operationType: .clientMessage
      )
    )

    let handle = try! channel.observeMessageReceived(from: recipient) { _, _ in }
    handle.cancel()

    // Register again and verify that no messages are sent again
    let _ = try! channel.observeMessageReceived(from: recipient) { _, _ in
      handlerNotCalledExpectation.fulfill()
    }

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testObserveReceivedMessage_throwsErrorIfMultipleObserversRegistered() {
    let recipient = UUID()

    XCTAssertNoThrow(try channel.observeMessageReceived(from: recipient) { _, _ in })
    XCTAssertThrowsError(
      try channel.observeMessageReceived(from: recipient) { _, _ in }
    ) { error in
      XCTAssertEqual(error as! SecuredCarChannelError, .observerAlreadyRegistered)
    }
  }

  func testObserveReceivedMessage_cancelObservation_allowsNewObserverToBeRegistered() {
    let recipient = UUID()

    let handle = try! channel.observeMessageReceived(from: recipient) { _, _ in }
    handle.cancel()

    XCTAssertNoThrow(try channel.observeMessageReceived(from: recipient) { _, _ in })
  }

  func testObserveReceivedMessage_differentRecipient_doesNotThrowError() {
    let recipient1 = UUID(uuidString: "8e8245ca-4af1-4b41-9799-48d3b4bc44e1")!
    let recipient2 = UUID(uuidString: "3bb74a19-5978-4756-b35f-491560333932")!

    XCTAssertNoThrow(try channel.observeMessageReceived(from: recipient1) { _, _ in })
    XCTAssertNoThrow(try channel.observeMessageReceived(from: recipient2) { _, _ in })
  }

  // MARK: - Send query tests.

  func testSendQuery_writesToStream() {
    let query = Query(request: Data("request".utf8), parameters: nil)
    let recipient = UUID()

    let queryID: Int32 = 2
    channel.queryID = queryID
    XCTAssertNoThrow(try channel.sendQuery(query, to: recipient) { _ in })

    XCTAssertEqual(messageStream.writtenEncryptedMessages.count, 1)

    let expectedMessage = try! query.toProtoData(queryID: queryID, sender: recipient)
    let expectedParams = MessageStreamParams(recipient: recipient, operationType: .query)

    XCTAssertEqual(messageStream.writtenEncryptedMessages[0].message, expectedMessage)
    XCTAssertEqual(messageStream.writtenEncryptedMessages[0].params, expectedParams)
  }

  func testSendQuery_throwsErrorIfInvalid() {
    // Simulate the car disconnecting.
    car.state = .disconnected

    let query = Query(request: Data("request".utf8), parameters: nil)

    XCTAssertThrowsError(
      try channel.sendQuery(query, to: UUID()) { _ in
        XCTFail("Completion handler should not be called.")
      }
    ) { error in
      XCTAssertEqual(error as! SecuredCarChannelError, .invalidChannel)
    }
  }

  func testSendQueryAsync_throwsErrorIfInvalid() async {
    // Simulate the car disconnecting.
    car.state = .disconnected

    let query = Query(request: Data("request".utf8), parameters: nil)

    do {
      _ = try await channel.sendQuery(query, to: UUID())
      XCTFail()
    } catch {
      XCTAssertEqual(error as! SecuredCarChannelError, .invalidChannel)
    }
  }

  func testQueryAsync_queryResponseIsReturned() async {
    let queryID: Int32 = 4
    channel.queryID = queryID

    let recipient = UUID()
    let expectedQueryResponse =
      QueryResponse(id: queryID, isSuccessful: true, response: Data("response".utf8))
    messageStream.autoReply = (
      message: try! expectedQueryResponse.toProtoData(),
      params: MessageStreamParams(recipient: recipient, operationType: .queryResponse)
    )

    let query = Query(request: Data("request".utf8), parameters: nil)
    let queryResponse = try! await channel.sendQuery(query, to: recipient)

    XCTAssertEqual(queryResponse, expectedQueryResponse)
  }

  func testConfiguresUsingFeatureProvider() {
    let featureProvider = ChannelFeatureProviderMock(userRole: .driver)
    var completed = false

    channel.configure(using: featureProvider) { _ in
      completed = true
    }

    XCTAssertTrue(completed)
    XCTAssertTrue(featureProvider.requestUserRoleCalled)
    XCTAssertNotNil(channel.userRole)
    XCTAssertTrue(channel.userRole?.isDriver ?? false)
  }

  // MARK: - Query response tests.

  func testQueryResponse_WithMatchingQueryID_notifiesCompletionHandler() {
    let handlerCalledExpectation = expectation(description: "Completion handler called.")

    let queryID: Int32 = 4
    channel.queryID = queryID

    let recipient = UUID()
    let query = Query(request: Data("request".utf8), parameters: nil)
    let expectedQueryResponse =
      QueryResponse(id: queryID, isSuccessful: true, response: Data("response".utf8))

    try! channel.sendQuery(query, to: recipient) { queryResponse in
      XCTAssertEqual(queryResponse, expectedQueryResponse)
      handlerCalledExpectation.fulfill()
    }

    messageStream.triggerMessageReceived(
      try! expectedQueryResponse.toProtoData(),
      params: MessageStreamParams(recipient: recipient, operationType: .queryResponse)
    )

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  func testQueryResponse_WithNoMatchingQueryID_doesNotNotifyCompletionHandler() {
    let handlerCalledExpectation = expectation(description: "Completion handler called.")
    handlerCalledExpectation.isInverted = true

    let queryID: Int32 = 4
    let wrongQueryId: Int32 = 10
    channel.queryID = queryID

    let recipient = UUID()
    let query = Query(request: Data("request".utf8), parameters: nil)
    let expectedQueryResponse =
      QueryResponse(id: wrongQueryId, isSuccessful: true, response: Data("response".utf8))

    try! channel.sendQuery(query, to: recipient) { _ in }

    messageStream.triggerMessageReceived(
      try! expectedQueryResponse.toProtoData(),
      params: MessageStreamParams(recipient: recipient, operationType: .queryResponse)
    )

    // Waiting for 1 second because the message should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if let error = error {
        XCTFail("waitForExpectationsWithTimeout encountered error: \(error)")
      }
    }
  }

  // MARK: - Query observations

  func testQueryObservation_throwsErrorIfMultipleObserversRegistered() {
    let recipient = UUID()

    XCTAssertNoThrow(try channel.observeQueryReceived(from: recipient) { _, _, _ in })

    // Second call to register on same recipient should throw error.
    XCTAssertThrowsError(try channel.observeQueryReceived(from: recipient) { _, _, _ in }) {
      error in
      XCTAssertEqual(error as! SecuredCarChannelError, .observerAlreadyRegistered)
    }
  }

  func testQueryObservation_notifiesCorrectObservation() {
    let observerCalled = expectation(description: "Correct observation called")
    let observerNotCalled = expectation(description: "Incorrect observation called")
    observerNotCalled.isInverted = true

    let recipient = UUID(uuidString: "28092c2c-3b28-4aa6-ad0f-99d2e8c72468")!
    let expectedSender = UUID(uuidString: "dd17ffb7-496f-4e5d-83be-b39048d46a26")!
    let otherRecipient = UUID(uuidString: "9205bf88-bcf0-4faa-8c67-c3f5a740ff30")!

    let expectedQueryID: Int32 = 5
    let expectedQuery = Query(request: Data("request".utf8), parameters: Data())

    XCTAssertNoThrow(
      try channel.observeQueryReceived(from: recipient) { queryID, sender, query in
        XCTAssertEqual(queryID, expectedQueryID)
        XCTAssertEqual(sender, expectedSender)
        XCTAssertEqual(query, expectedQuery)
        observerCalled.fulfill()
      })

    XCTAssertNoThrow(
      try channel.observeQueryReceived(from: otherRecipient) { _, _, _ in
        observerNotCalled.fulfill()
      })

    let queryData = try! expectedQuery.toProtoData(queryID: expectedQueryID, sender: expectedSender)
    messageStream.triggerMessageReceived(
      queryData,
      params: MessageStreamParams(recipient: recipient, operationType: .query)
    )

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Correct observation was not called")
      }
    }
  }

  func testQueryObservation_notifiesCorrectObservation_withMissedQueries() {
    let observerCalled = expectation(description: "Correct observation called")
    let observerNotCalled = expectation(description: "Incorrect observation called")
    observerNotCalled.isInverted = true

    let recipient = UUID(uuidString: "28092c2c-3b28-4aa6-ad0f-99d2e8c72468")!
    let expectedSender = UUID(uuidString: "dd17ffb7-496f-4e5d-83be-b39048d46a26")!
    let otherRecipient = UUID(uuidString: "9205bf88-bcf0-4faa-8c67-c3f5a740ff30")!

    let expectedQueryID: Int32 = 5
    let expectedQuery = Query(request: Data("request".utf8), parameters: Data())

    // Send the message before registration of observers.
    let queryData = try! expectedQuery.toProtoData(queryID: expectedQueryID, sender: expectedSender)
    messageStream.triggerMessageReceived(
      queryData,
      params: MessageStreamParams(recipient: recipient, operationType: .query)
    )

    // Now, register the observers.
    XCTAssertNoThrow(
      try channel.observeQueryReceived(from: recipient) { queryID, sender, query in
        XCTAssertEqual(queryID, expectedQueryID)
        XCTAssertEqual(sender, expectedSender)
        XCTAssertEqual(query, expectedQuery)
        observerCalled.fulfill()
      })

    XCTAssertNoThrow(
      try channel.observeQueryReceived(from: otherRecipient) { _, _, _ in
        observerNotCalled.fulfill()
      })

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Correct observation was not called")
      }
    }
  }

  func testQueryObservation_notifiesCorrectObservation_withMissedQueries_onlyOnce() {
    let observerNotCalled = expectation(description: "Incorrect observation called")
    observerNotCalled.isInverted = true

    let recipient = UUID(uuidString: "28092c2c-3b28-4aa6-ad0f-99d2e8c72468")!
    let sender = UUID(uuidString: "dd17ffb7-496f-4e5d-83be-b39048d46a26")!

    let queryID: Int32 = 5
    let query = Query(request: Data("request".utf8), parameters: Data())

    // Send the message before registration of observers.
    let queryData = try! query.toProtoData(queryID: queryID, sender: sender)
    messageStream.triggerMessageReceived(
      queryData,
      params: MessageStreamParams(recipient: recipient, operationType: .query)
    )

    let handle = try! channel.observeQueryReceived(from: recipient) { _, _, _ in }
    handle.cancel()

    // This second register should not trigger any missed queries.
    let _ = try! channel.observeQueryReceived(from: recipient) { _, _, _ in
      observerNotCalled.fulfill()
    }

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Correct observation was not called")
      }
    }
  }

  func testQueryObservation_cancelsCorrectObservation() {
    let observerCalled = expectation(description: "Correct observation called")
    let observerNotCalled = expectation(description: "Incorrect observation called")
    observerNotCalled.isInverted = true

    let recipient = UUID(uuidString: "28092c2c-3b28-4aa6-ad0f-99d2e8c72468")!
    let expectedSender = UUID(uuidString: "dd17ffb7-496f-4e5d-83be-b39048d46a26")!
    let otherRecipient = UUID(uuidString: "9205bf88-bcf0-4faa-8c67-c3f5a740ff30")!

    let expectedQueryID: Int32 = 5
    let expectedQuery = Query(request: Data("request".utf8), parameters: Data())

    XCTAssertNoThrow(
      try channel.observeQueryReceived(from: recipient) { queryID, sender, query in
        XCTAssertEqual(queryID, expectedQueryID)
        XCTAssertEqual(sender, expectedSender)
        XCTAssertEqual(query, expectedQuery)
        observerCalled.fulfill()
      })

    let observationToCancel = try! channel.observeQueryReceived(from: otherRecipient) { _, _, _ in
      observerNotCalled.fulfill()
    }
    observationToCancel.cancel()

    let queryData = try! expectedQuery.toProtoData(queryID: expectedQueryID, sender: expectedSender)
    messageStream.triggerMessageReceived(
      queryData,
      params: MessageStreamParams(recipient: recipient, operationType: .query)
    )

    messageStream.triggerMessageReceived(
      queryData,
      params: MessageStreamParams(recipient: otherRecipient, operationType: .query)
    )

    // Waiting for 1 second because the query should notify immediately.
    waitForExpectations(timeout: 1) { error in
      if error != nil {
        XCTFail("Correct observation was not called")
      }
    }
  }

  // MARK: - Send query response test

  func testSendQueryResponse_writesToStream() {
    let recipient = UUID()
    let queryResponse = QueryResponse(id: 5, isSuccessful: true, response: Data("response".utf8))

    XCTAssertNoThrow(try channel.sendQueryResponse(queryResponse, to: recipient))

    XCTAssertEqual(messageStream.writtenEncryptedMessages.count, 1)
    XCTAssertEqual(
      messageStream.writtenEncryptedMessages[0].message, try! queryResponse.toProtoData())

    let expectedParams = MessageStreamParams(recipient: recipient, operationType: .queryResponse)
    XCTAssertEqual(messageStream.writtenEncryptedMessages[0].params, expectedParams)
  }

  // MARK: - Helper functions

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}
