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
import AndroidAutoSecureChannel
import CoreBluetooth
import LocalAuthentication
import XCTest
import AndroidAutoTrustAgentProtos

@testable import AndroidAutoConnectedDeviceManager

/// Unit tests for `TrustAgentManager`.
@MainActor class TrustAgentManagerTest: XCTestCase {
  // The default name that is used when `setUpValidChannel(withCarId:)` is called.
  private let defaultChannelName = "mock car"
  private let testCarId1 = "testCarId1"
  private let testCarId2 = "testCarId2"
  private let testCar1 = Car(id: "testCarId1", name: "mock car 1")
  private let testCar2 = Car(id: "testCarId2", name: "mock car 2")

  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var escrowTokenManager: EscrowTokenManagerFake!
  private var trustAgentStorage: TrustAgentManagerStorageFake!
  private var config: TrustAgentConfigFake!

  private var trustAgentManager: TrustAgentManager!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    connectedCarManagerMock = ConnectedCarManagerMock()
    escrowTokenManager = EscrowTokenManagerFake()
    trustAgentStorage = TrustAgentManagerStorageFake()
    config = TrustAgentConfigFake()

    trustAgentManager = TrustAgentManager(
      connectedCarManager: connectedCarManagerMock,
      escrowTokenManager: escrowTokenManager,
      trustAgentStorage: trustAgentStorage,
      config: config
    )
  }

  // MARK: - Enrollment error tests

  func testEnroll_carNotConnected_notifiesDelegateOfError() {
    let car = Car(id: testCarId1, name: "name")
    let delegate = TrustAgentDelegateMock()

    trustAgentManager.delegate = delegate
    XCTAssertNoThrow(try trustAgentManager.enroll(car))

    // No SecuredCarChannel associated with the given car, so the enroll car should notify
    // delegates.
    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .carNotConnected)
  }

  func testEnroll_tokenGenerationFailed_notifiesDelegateOfError() {
    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    escrowTokenManager.generateTokenSucceeds = false
    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    // No escrow token set on the EscrowTokenManagerFake, so the generation of the token should
    // fail.
    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .cannotGenerateToken)
  }

  func testEnroll_writeFails_notifiesDelegateOfError() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Ensure writes fail.
    channel.isValid = false

    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .cannotSendToken)
  }

  func testEnroll_handleStorageFailure_notifiesDelegate() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    // Specify that handle storage will fail
    escrowTokenManager.storeHandleSucceeds = false

    // Now trigger the handle being sent.
    let messageData = makeMessageData(type: .handle)
    channel.triggerMessageReceived(messageData, from: TrustAgentManager.recipientUUID)

    // Delegate should be notified.
    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .cannotStoreHandle)
  }

  // MARK: - Enrollment tests

  func testEnroll_validFlow() {
    runThroughEnrollmentFlow(withCarId: testCarId1)
  }

  func testEnroll_validFlow_isEnrolledReturnsTrue() {
    runThroughEnrollmentFlow(withCarId: testCar1.id)
    XCTAssertTrue(trustAgentManager.isEnrolled(with: testCar1))
  }

  func testEnroll_successful_notifiesDelegate() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    // Verify delegate notified.
    XCTAssertTrue(delegate.didCompleteEnrollingCalled)
    XCTAssertEqual(delegate.enrolledCar, channel.car)
  }

  func testEnroll_eachRequestSendsEscrowToken() {
    let car = Car(id: testCarId1, name: "name")
    let channel = SecuredCarChannelMock(car: car)

    // Car needs to be connected before enrollment.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertNoThrow(try trustAgentManager.enroll(car))
    XCTAssertNoThrow(try trustAgentManager.enroll(car))

    XCTAssertNotNil(escrowTokenManager.tokens[car.id])
    let token = escrowTokenManager.tokens[car.id]!

    let tokenMessage = makeMessageData(type: .escrowToken, payload: token)

    // Each request should have sent a new escrow token.
    XCTAssertEqual(channel.writtenMessages.count, 2)
    XCTAssertEqual(channel.writtenMessages[0], tokenMessage)
    XCTAssertEqual(channel.writtenMessages[1], tokenMessage)
  }

  func testEnroll_canEnrollAfterStopCall() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    // Verify only escrow token written.
    XCTAssertEqual(channel.writtenMessages.count, 1)

    // Stop enrollments and attempt to enroll the same car.
    trustAgentManager.stopEnrollment(for: channel.car)

    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    // Call should succeed with another token written.
    XCTAssertEqual(channel.writtenMessages.count, 2)
  }

  func testEnroll_DoesNotInterfereWithUnlock() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let enrollingChannel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: enrollingChannel)
    XCTAssertNoThrow(try trustAgentManager.enroll(enrollingChannel.car))

    // Escrow token written.
    XCTAssertEqual(enrollingChannel.writtenMessages.count, 1)

    // Enrollment now waiting for handle. Trigger the connection of an associated car.
    setUpAsEnrolled(carId: testCarId2)
    let enrolledChannel = SecuredCarChannelMock(car: testCar2)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: enrolledChannel)

    // Ensure only one thing written for this new channel (the phone credentials).
    XCTAssertEqual(enrolledChannel.writtenMessages.count, 1)
    XCTAssertEqual(enrollingChannel.writtenMessages.count, 1)

    // Trigger message response from the enrolled channel. Should not affect the enrolling channel.
    respondWithAck(over: enrolledChannel)

    // Unlock signaling should have occurred.
    XCTAssertTrue(delegate.didFinishUnlockingCalled)
    XCTAssertEqual(delegate.didUnlockCar!.id, enrolledChannel.id)

    // Enrollment should not have been affected.
    XCTAssertFalse(delegate.didCompleteEnrollingCalled)
  }

  func testStopEnrolling_ignoresSentHandle() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    trustAgentManager.stopEnrollment(for: channel.car)

    // Now trigger the handle being sent.
    let handle = Data("handle".utf8)
    channel.triggerMessageReceived(handle, from: TrustAgentManager.recipientUUID)

    // Verify delegate is not notified and no handle stored.
    XCTAssertFalse(delegate.didCompleteEnrollingCalled)
    XCTAssertNil(escrowTokenManager.handles[testCarId1])
  }

  // MARK: - Car initiated enrollment tests.

  func testStartEnrollment_sendsEscrowToken() {
    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Trigger a message from the car with the request to enroll.
    let startEnrollmentMessage = makeMessageData(type: .startEnrollment)
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )

    XCTAssertNotNil(escrowTokenManager.tokens[testCar1.id])
    let escrowToken = escrowTokenManager.tokens[testCar1.id]!

    // Verify an escrow token was sent.
    XCTAssertEqual(channel.writtenMessages.count, 1)

    let escrowTokenMessage = makeMessageData(type: .escrowToken, payload: escrowToken)
    XCTAssertEqual(channel.writtenMessages[0], escrowTokenMessage)
  }

  func testStartEnrollment_sendsEscrowTokenMultipleTimes() {
    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Trigger two message from the car with the request to enroll.
    let startEnrollmentMessage = makeMessageData(type: .startEnrollment)
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )

    XCTAssertNotNil(escrowTokenManager.tokens[testCar1.id])
    let escrowToken = escrowTokenManager.tokens[testCar1.id]!

    // Verify two escrow tokens were sent.
    XCTAssertEqual(channel.writtenMessages.count, 2)

    let escrowTokenMessage = makeMessageData(type: .escrowToken, payload: escrowToken)
    XCTAssertEqual(channel.writtenMessages[0], escrowTokenMessage)
    XCTAssertEqual(channel.writtenMessages[1], escrowTokenMessage)
  }

  func testStartEnrollment_notifiesDelegateIfError() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    escrowTokenManager.generateTokenSucceeds = false

    // Now trigger a message from the car with the request to enroll.
    let startEnrollmentMessage = makeMessageData(type: .startEnrollment)
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )

    // Delegate notified of error.
    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .cannotGenerateToken)
  }

  func testEnrollmentFails_NoPasscode() throws {
    let delegate = TrustAgentDelegateMock()
    config.isPasscodeRequired = true
    config.isPasscodeSet = false

    let channel = SecuredCarChannelMock(car: testCar1)
    trustAgentManager.delegate = delegate

    // Simulate the setup of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Now trigger a message from the car with the request to enroll.
    let startEnrollmentMessage = makeMessageData(type: .startEnrollment)
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )

    // Error message response sent back to car.
    XCTAssertEqual(channel.writtenMessages.count, 1)

    var responseError = Aae_Trustagent_TrustedDeviceError()
    responseError.type = .deviceNotSecured
    let payload = try responseError.serializedData()
    let messageData = makeMessageData(type: .error, payload: payload)

    XCTAssertEqual(channel.writtenMessages[0], messageData)

    // Delegate notified of error.
    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
  }

  func testStartEnrollment_sendsEscrowTokenIfAlreadyEnrolled() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Simulate that there is already a stored token for the car. Note: this is set up after the
    // secure channel setup to avoid unlock credentials being sent.
    setUpAsEnrolled(carId: testCar1.id)

    // Now trigger a message from the car with the request to enroll.
    let startEnrollmentMessage = makeMessageData(type: .startEnrollment)
    channel.triggerMessageReceived(
      startEnrollmentMessage,
      from: TrustAgentManager.recipientUUID
    )

    XCTAssertNotNil(escrowTokenManager.tokens[testCar1.id])
    let escrowToken = escrowTokenManager.tokens[testCar1.id]!

    XCTAssertEqual(channel.writtenMessages.count, 1)

    let escrowTokenMessage = makeMessageData(type: .escrowToken, payload: escrowToken)
    XCTAssertEqual(channel.writtenMessages[0], escrowTokenMessage)
  }

  // MARK: - Send phone credentials tests.

  func testSendPhoneCredentials_toSingleConnectedCar() {
    let (token, handle) = setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let phoneCredentials = makePhoneCredentials(token: token, handle: handle)
    let messageData = makeMessageData(type: .unlockCredentials, payload: phoneCredentials)

    XCTAssertEqual(channel.writtenMessages.count, 1)
    XCTAssertEqual(channel.writtenMessages[0], messageData)
  }

  func testSendPhoneCredentials_toMultipleConnectedCars() {
    let (token1, handle1) = setUpAsEnrolled(carId: testCarId1)
    let channel1 = SecuredCarChannelMock(car: testCar1)

    let (token2, handle2) = setUpAsEnrolled(carId: testCarId2)
    let channel2 = SecuredCarChannelMock(car: testCar2)

    // Simulate the set up of a secure channel.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel2)

    let phoneCredentials1 = makePhoneCredentials(token: token1, handle: handle1)
    let messageData1 = makeMessageData(
      type: .unlockCredentials, payload: phoneCredentials1)

    let phoneCredentials2 = makePhoneCredentials(token: token2, handle: handle2)
    let messageData2 = makeMessageData(
      type: .unlockCredentials, payload: phoneCredentials2)

    // Each car should receive separate writes.
    XCTAssertEqual(channel1.writtenMessages.count, 1)
    XCTAssertEqual(
      channel1.writtenMessages[0], messageData1)

    XCTAssertEqual(channel2.writtenMessages.count, 1)
    XCTAssertEqual(
      channel2.writtenMessages[0], messageData2)
  }

  func testSendPhoneCredentials_noPasscodeSetOrRequired_notEnrolled_doesNotthrowError() {
    let delegate = TrustAgentDelegateMock()
    config.isPasscodeRequired = true
    config.isPasscodeSet = true

    let channel = SecuredCarChannelMock(car: testCar1)
    trustAgentManager.delegate = delegate

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertFalse(delegate.didEncounterErrorCalled)
  }

  func testSendPhoneCredentials_passcodeRequired_throwsError() {
    let delegate = TrustAgentDelegateMock()
    config.isPasscodeRequired = true
    config.isPasscodeSet = false

    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)
    trustAgentManager.delegate = delegate

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .passcodeNotSet)
  }

  func testSendPhoneCredentials_deviceUnlockRequiredWithDeviceLocked_throwsError() {
    let delegate = TrustAgentDelegateMock()
    config.setDeviceUnlockRequired(true, for: testCar1)
    config.isDeviceUnlocked = false

    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)
    trustAgentManager.delegate = delegate

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(delegate.didEncounterErrorCalled)
    XCTAssertEqual(delegate.error, .deviceLocked)
  }

  // MARK: - Delegate notification tests.

  func testUnlock_notifiesDelegateOfStart() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    setUpAsEnrolled(carId: testCarId1)

    // Simulate the set up of a secure channel.
    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(delegate.didStartUnlockingCalled)
    XCTAssertEqual(delegate.didStartUnlockingCar!.id, channel.id)
  }

  func testUnlock_notifiesDelegateOfStart_afterSecuredChannelNotification() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    setUpAsEnrolled(carId: testCarId1)

    // No cars to unlock yet.
    XCTAssertFalse(delegate.didStartUnlockingCalled)

    // Now notify of the car being secured for communication. Delegate should be notified.
    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(delegate.didStartUnlockingCalled)
    XCTAssertEqual(delegate.didStartUnlockingCar!.id, channel.id)
  }

  func testSuccessfulUnlock_ofConnectedCar_notifiesDelegate() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    setUpAsEnrolled(carId: testCarId1)

    // Simulate the set up of a secure channel.
    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Nothing should have been notified on the delegate yet.
    XCTAssertFalse(delegate.didFinishUnlockingCalled)

    // Now notify an ACK was received.
    respondWithAck(over: channel)

    XCTAssertTrue(delegate.didFinishUnlockingCalled)
    XCTAssertEqual(delegate.didUnlockCar!.id, channel.id)
  }

  // MARK: - Error tests.

  func testNoValidToken_doesNothing() {
    let channel = SecuredCarChannelMock(car: testCar1)
    let delegate = TrustAgentDelegateMock()

    trustAgentManager.delegate = delegate

    // Simulate the set up of a secure channel.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // No message should have been written.
    XCTAssertTrue(channel.writtenMessages.isEmpty)
  }

  func testNoValidHandle_doesNothing() {
    let channel = SecuredCarChannelMock(car: testCar1)
    let delegate = TrustAgentDelegateMock()

    trustAgentManager.delegate = delegate

    // Valid token but no handle.
    escrowTokenManager.tokens[testCarId1] = Data("token".utf8)

    // Simulate the set up of a secure channel.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // No message should have been written.
    XCTAssertTrue(channel.writtenMessages.isEmpty)
  }

  func testReceivedMessage_fromWrongUUID_doesNotNotifyDelegate() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    // Nothing should have been notified on the delegate yet.
    XCTAssertFalse(delegate.didFinishUnlockingCalled)

    // Using a UUID that is not TrustAgentManager.recipientUUID.
    let wrongRecipient = UUID(uuidString: "00000000-0000-4000-8000-000000000000")!
    let acknowledgementMessageData = makeMessageData(type: .ack)

    setUpAsEnrolled(carId: testCarId1)

    // Now trigger a car has connected and send an ACK.
    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    channel.triggerMessageReceived(acknowledgementMessageData, from: wrongRecipient)

    // Delegate should not have been notified because the recipient UUID is wrong.
    XCTAssertFalse(delegate.didFinishUnlockingCalled)
  }

  // MARK: - Disconnection tests

  func testDisconnection_duringEnrollmentNotifiesDelegate() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = SecuredCarChannelMock(car: testCar1)
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertNoThrow(try trustAgentManager.enroll(channel.car))

    // Now trigger the car was disconnected in the middle of the enrollment
    connectedCarManagerMock.triggerDisconnection(for: channel.car)

    XCTAssertTrue(delegate.didEncounterEnrollingErrorCalled)
    XCTAssertEqual(delegate.enrollingError, .carNotConnected)
  }

  // MARK: - Dissociation tests

  func testDissociation_clearsStoredTokenAndHandleAndUnlockHistory() {
    runThroughEnrollmentFlow(withCarId: testCar1.id)

    // Trigger that this enrolled car was dissociated
    connectedCarManagerMock.triggerDissociation(for: testCar1)

    XCTAssertFalse(trustAgentManager.isEnrolled(with: testCar1))
    XCTAssertTrue(trustAgentManager.unlockHistory(for: testCar1).isEmpty)
  }

  func testDissociation_retainsTokenAndHandleForAssociatedCars() {
    setUpAsEnrolled(carId: testCar1.id)

    // Trigger a dissociation for an unenrolled car.
    let unenrolledCar = Car(id: "unenrolledId", name: "mock")
    connectedCarManagerMock.triggerDissociation(for: unenrolledCar)

    // Car should still be enrolled.
    XCTAssertTrue(trustAgentManager.isEnrolled(with: testCar1))
  }

  // MARK: - Stop enrollment tests.

  func testStopEnrollment_notifiesCallback() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    runThroughEnrollmentFlow(withCarId: testCarId1)

    trustAgentManager.stopEnrollment(for: testCar1)

    XCTAssertTrue(delegate.didUnenrollCalled)
    XCTAssertEqual(delegate.unenrolledCar, testCar1)
    XCTAssertFalse(delegate.unenrollInitiatedFromCar)
  }

  func testStopEnrollment_doesNotNotifyCallbackIfUnenrolled() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    trustAgentManager.stopEnrollment(for: testCar1)

    XCTAssertFalse(delegate.didUnenrollCalled)
  }

  // MARK: - Feature status sync tests.

  func testFeatureSync_syncsStatusFromCar() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    // The car sends a message notifying that trusted device is now disabled.
    let status = makeDisabledStatusMessage()
    let statusMessage = makeMessageData(type: .stateSync, payload: status)
    channel.triggerMessageReceived(statusMessage, from: TrustAgentManager.recipientUUID)

    XCTAssertFalse(trustAgentManager.isEnrolled(with: testCar1))

    XCTAssertTrue(delegate.didUnenrollCalled)
    XCTAssertEqual(delegate.unenrolledCar, testCar1)
    XCTAssertTrue(delegate.unenrollInitiatedFromCar)
  }

  func testFeatureSync_doesNotDuplicateStatusBackToCar() {
    let delegate = TrustAgentDelegateMock()
    trustAgentManager.delegate = delegate

    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)
    let messageCount = channel.writtenMessages.count

    // The car sends a message notifying that trusted device is now disabled.
    let status = makeDisabledStatusMessage()
    let statusMessage = makeMessageData(type: .stateSync, payload: status)
    channel.triggerMessageReceived(statusMessage, from: TrustAgentManager.recipientUUID)

    // Verify no additional messages send to the car.
    XCTAssertEqual(channel.writtenMessages.count, messageCount)
  }

  func testFeatureSync_doesNotSendAnyStatusForUnenrolledCar() {
    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssert(channel.writtenMessages.isEmpty)
  }

  func testFeatureSync_ignoresEnabledStatusFromUnenrolledCar() {
    let channel = SecuredCarChannelMock(car: testCar1)

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // The car sends a message notifying that trusted device is now enabled.
    let status = makeEnabledStatusMessage()
    let statusMessage = makeMessageData(type: .stateSync, payload: status)
    channel.triggerMessageReceived(statusMessage, from: TrustAgentManager.recipientUUID)

    XCTAssertFalse(trustAgentManager.isEnrolled(with: testCar1))
  }

  func testFeatureSync_sendsStatusMessageToCarWhenUnenrolled() {
    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    trustAgentManager.stopEnrollment(for: testCar1)

    let status = makeDisabledStatusMessage()
    let expectedMessage = makeMessageData(type: .stateSync, payload: status)

    let lastMessage = channel.writtenMessages.last
    XCTAssertEqual(lastMessage, expectedMessage)
  }

  func testFeatureSync_doesNotSendOnDisassociation() {
    let channel = runThroughEnrollmentFlow(withCarId: testCar1.id)
    let messageCount = channel.writtenMessages.count

    // Trigger that this enrolled car was dissociated
    connectedCarManagerMock.triggerDissociation(for: testCar1)

    // Verify no new messages sent after the car has been disassociated
    XCTAssertEqual(channel.writtenMessages.count, messageCount)
  }

  func testFeatureSync_syncsOnNextConnection() {
    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)
    let messageCount = channel.writtenMessages.count

    // The car is disconnected and enrollment is cleared.
    connectedCarManagerMock.triggerDisconnection(for: channel.car)
    trustAgentManager.stopEnrollment(for: testCar1)

    XCTAssertEqual(channel.writtenMessages.count, messageCount)

    // Now simulate the car has connected again.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // The car should now send a message notifying that trusted device is now disabled.
    let status = makeDisabledStatusMessage()
    let expectedMessage = makeMessageData(type: .stateSync, payload: status)

    XCTAssertEqual(channel.writtenMessages.count, messageCount + 1)
    XCTAssertEqual(channel.writtenMessages.last, expectedMessage)
  }

  func testFeatureSync_doesNotSyncIfPreviousSyncSuccessful() {
    let channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    // The car is disconnected and enrollment is cleared.
    connectedCarManagerMock.triggerDisconnection(for: channel.car)
    trustAgentManager.stopEnrollment(for: testCar1)

    // Now simulate the car has connected again, which should send a sync message and then
    // disconnecting.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)
    connectedCarManagerMock.triggerDisconnection(for: channel.car)

    let messageCount = channel.writtenMessages.count

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Previous sync should have been successful, so no new message should be sent.
    XCTAssertEqual(channel.writtenMessages.count, messageCount)
  }

  func testFeatureSync_clearsOnDisassociation() {
    var channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    // The car is disconnected and enrollment is cleared.
    connectedCarManagerMock.triggerDisconnection(for: channel.car)
    trustAgentManager.stopEnrollment(for: testCar1)

    // Trigger that this enrolled car was dissociated
    connectedCarManagerMock.triggerDissociation(for: testCar1)

    // Now simulate the car has enrolled again.
    channel = runThroughEnrollmentFlow(withCarId: testCarId1)

    let status = makeDisabledStatusMessage()
    let expectedMessage = makeMessageData(type: .stateSync, payload: status)

    // The car should not send a message notifying that trusted device is now disabled.
    XCTAssertFalse(channel.writtenMessages.contains(expectedMessage))
  }

  // MARK: - Unlock history tests.

  func testUnlockHistory_emptyIfNoUnlocks() {
    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertTrue(trustAgentManager.unlockHistory(for: testCar1).isEmpty)
  }

  func testSuccessfulUnlock_storesUnlockHistory() {
    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Respond with an ACK confirming that the unlock was successful.
    respondWithAck(over: channel)

    XCTAssert(trustAgentManager.unlockHistory(for: testCar1).count == 1)
  }

  func testSuccessfulUnlock_notStoredIfHistoryDisabled() {
    config.isUnlockHistoryEnabled = false

    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Respond with an ACK confirming that the unlock was successful.
    respondWithAck(over: channel)

    XCTAssert(trustAgentManager.unlockHistory(for: testCar1).isEmpty)
  }

  func testUnlockHistory_keepsHistorySeparateForCars() {
    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Respond with an ACK confirming that the unlock was successful.
    respondWithAck(over: channel)

    // Verify that another car still does not have any unlock history
    XCTAssertTrue(trustAgentManager.unlockHistory(for: testCar2).isEmpty)
  }

  func testClearUnlockHistory() {
    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Respond with an ACK confirming that the unlock was successful.
    respondWithAck(over: channel)

    trustAgentManager.clearUnlockHistory(for: testCar1)

    XCTAssertTrue(trustAgentManager.unlockHistory(for: testCar1).isEmpty)
  }

  func testClearUnlockHistory_clearsOnlyForSelectedCar() {
    // Set up unlock history for unrelated car.
    trustAgentStorage.addUnlockDate(Date(), for: testCar2)

    setUpAsEnrolled(carId: testCarId1)
    let channel = SecuredCarChannelMock(car: testCar1)

    // Simulate the set up of a secure channel, which should trigger the unlock flow.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Respond with an ACK confirming that the unlock was successful.
    respondWithAck(over: channel)

    trustAgentManager.clearUnlockHistory(for: testCar1)

    XCTAssert(trustAgentManager.unlockHistory(for: testCar2).count == 1)
  }

  func testUnlockHistory_clearedIfConfigChanged() {
    // Set up unlock history for car.
    trustAgentStorage.addUnlockDate(Date(), for: testCar1)

    // Create a new trust agent manager with the same config.
    config.isUnlockHistoryEnabled = false
    trustAgentManager = TrustAgentManager(
      connectedCarManager: connectedCarManagerMock,
      escrowTokenManager: escrowTokenManager,
      trustAgentStorage: trustAgentStorage,
      config: config
    )

    XCTAssert(trustAgentManager.unlockHistory(for: testCar1).isEmpty)
  }

  // MARK: - Convenience methods.

  /// Runs through all the steps that are required for a car with the given `id` to be enrolled.
  ///
  /// This method also asserts the steps for the correct data being sent.
  ///
  /// - Returns: A mock channel that has been enrolled.
  @discardableResult
  private func runThroughEnrollmentFlow(withCarId id: String) -> SecuredCarChannelMock {
    let car = Car(id: id, name: defaultChannelName)
    let channel = SecuredCarChannelMock(car: car)

    // Car needs to be connected before enrollment.
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    XCTAssertNoThrow(try trustAgentManager.enroll(car))

    XCTAssertNotNil(escrowTokenManager.tokens[car.id])
    let token = escrowTokenManager.tokens[car.id]!

    let tokenMessage = makeMessageData(type: .escrowToken, payload: token)

    // Escrow token should be sent.
    XCTAssertEqual(channel.writtenMessages.count, 1)
    XCTAssertEqual(channel.writtenMessages[0], tokenMessage)

    // Now trigger the handle being sent.
    let handle = Data("handle".utf8)
    let handleMessage = makeMessageData(type: .handle, payload: handle)
    channel.triggerMessageReceived(handleMessage, from: TrustAgentManager.recipientUUID)

    // Verify the confirmation message is sent.
    let messageData = makeMessageData(type: .ack)
    XCTAssertEqual(channel.writtenMessages.count, 2)
    XCTAssertEqual(channel.writtenMessages[1], messageData)

    return channel
  }

  /// Simply sets up the car with the given [id] as enrolled and returns the registered token and
  /// handle.
  @discardableResult
  private func setUpAsEnrolled(carId: String) -> (token: Data, handle: Data) {
    let token = escrowTokenManager.generateAndStoreToken(for: carId)!

    let handle = Data("handle".utf8)
    let _ = escrowTokenManager.storeHandle(handle, for: carId)
    return (token, handle)
  }

  /// Simulates an `ACK` message being sent over the given channel.
  private func respondWithAck(over channel: SecuredCarChannelMock) {
    let acknowledgementMessage = makeMessageData(type: .ack, payload: nil)
    channel.triggerMessageReceived(acknowledgementMessage, from: TrustAgentManager.recipientUUID)
  }

  /// Creates a trusted device message from the specified type and optional payload.
  ///
  /// - Parameters:
  ///   - type: The message type.
  ///   - payload: The optional message payload data.
  /// - Returns: The generated trusted device message data.
  /// - Throws: An error if the message fails to serialize to data
  private func makeMessageData(
    type: TrustedDeviceMessage.MessageType,
    payload: Data? = nil
  ) -> Data {
    var message = TrustedDeviceMessage()
    message.version = 2
    message.type = type
    if let payload = payload {
      message.payload = payload
    }
    return try! message.serializedData()
  }

  private func makeEnabledStatusMessage() -> Data {
    var status = TrustedDeviceState()
    status.enabled = true
    return try! status.serializedData()
  }

  private func makeDisabledStatusMessage() -> Data {
    var status = TrustedDeviceState()
    status.enabled = false
    return try! status.serializedData()
  }

  private func makePhoneCredentials(token: Data, handle: Data) -> Data {
    var phoneCredentials = Aae_Trustagent_PhoneCredentials()

    phoneCredentials.escrowToken = token
    phoneCredentials.handle = handle

    return try! phoneCredentials.serializedData()
  }

  private func makeMockError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}
