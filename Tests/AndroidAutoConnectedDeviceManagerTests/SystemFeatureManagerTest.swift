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
import CoreBluetooth
import XCTest
@_implementationOnly import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager

private typealias SystemQuery = Com_Google_Companionprotos_SystemQuery
private typealias FeatureSupportStatus = Com_Google_Companionprotos_FeatureSupportStatus
private typealias FeatureSupportResponse = Com_Google_Companionprotos_FeatureSupportResponse
private typealias SystemQueryType = Com_Google_Companionprotos_SystemQueryType
private typealias SystemUserRoleResponse = Com_Google_Companionprotos_SystemUserRoleResponse
typealias SystemUserRole = Com_Google_Companionprotos_SystemUserRole

/// Unit tests for `SystemFeatureManager`.
@MainActor class SystemFeatureManagerTest: XCTestCase {
  private let deviceName = "DeviceName"
  private let appName = "appName"
  private var car: Car!

  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var channel: SecuredCarChannelMock!
  private var manager: SystemFeatureManager!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    connectedCarManagerMock = ConnectedCarManagerMock()
    car = Car(id: "id", name: "name")
    channel = SecuredCarChannelMock(car: car)

    manager = SystemFeatureManager(
      connectedCarManager: connectedCarManagerMock,
      nameProvider: FakeDevice(name: deviceName),
      appNameProvider: FakeAppNameProvider(appName: appName)
    )
  }

  // MARK: - Device name tests

  func testOnValidQuery_sendsDeviceName() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let request = createSystemQuery(type: SystemQueryType.deviceName)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: Data(deviceName.utf8)
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  // MARK: - App name tests

  func testOnValidQuery_sendsAppName() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let request = createSystemQuery(type: SystemQueryType.appName)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: Data(appName.utf8)
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testOnAppNameRetrievalFaiL_sendsUnsuccessfulQueryResponse() {
    manager = SystemFeatureManager(
      connectedCarManager: connectedCarManagerMock,
      nameProvider: FakeDevice(name: deviceName),
      appNameProvider: FakeAppNameProvider(appName: nil)
    )
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let request = createSystemQuery(type: SystemQueryType.appName)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: false,
      response: Data()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testBundleExtension_looksUpAppName() {
    // If the `test_host` ever changes, this value will need to change.
    XCTAssertEqual(Bundle.main.appName, "TrustAgentSample")
  }

  // MARK: - User Role Request

  func testRequestUserRole_callsCompletionWithDriverRole() throws {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    var completionCalled = false
    let queryID = channel.queryID
    var userRole: UserRole? = nil
    manager.requestUserRole(with: channel) {
      userRole = $0
      completionCalled = true
    }

    var roleResponse = SystemUserRoleResponse()
    roleResponse.role = .driver
    let queryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try roleResponse.serializedData()
    )
    channel.triggerQueryResponse(queryResponse)

    XCTAssertEqual(channel.writtenQueries.count, 1)
    XCTAssertTrue(completionCalled)
    XCTAssertNotNil(userRole)
    XCTAssertTrue(userRole?.isDriver ?? false)
    XCTAssertFalse(userRole?.isPassenger ?? false)
  }

  func testRequestUserRole_callsCompletionWithPassengerRole() throws {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    var completionCalled = false
    let queryID = channel.queryID
    var userRole: UserRole? = nil
    manager.requestUserRole(with: channel) {
      userRole = $0
      completionCalled = true
    }

    var roleResponse = SystemUserRoleResponse()
    roleResponse.role = .passenger
    let queryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try roleResponse.serializedData()
    )
    channel.triggerQueryResponse(queryResponse)

    XCTAssertEqual(channel.writtenQueries.count, 1)
    XCTAssertTrue(completionCalled)
    XCTAssertNotNil(userRole)
    XCTAssertFalse(userRole?.isDriver ?? false)
    XCTAssertTrue(userRole?.isPassenger ?? false)
  }

  func testRequestUserRole_unsuccessfulResponse() throws {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    var completionCalled = false
    let queryID = channel.queryID
    var userRole: UserRole? = nil
    manager.requestUserRole(with: channel) {
      userRole = $0
      completionCalled = true
    }

    var roleResponse = SystemUserRoleResponse()
    roleResponse.role = .passenger
    let queryResponse = QueryResponse(
      id: queryID,
      isSuccessful: false,
      response: try roleResponse.serializedData()
    )
    channel.triggerQueryResponse(queryResponse)

    XCTAssertEqual(channel.writtenQueries.count, 1)
    XCTAssertTrue(completionCalled)
    XCTAssertNil(userRole)
  }

  // MARK: - Feature support status tests

  func testFeatureSupportStatus_supportedFeature_sendsSupportedStatus() {
    let featureID = UUID(uuidString: "dbca154b-f9c8-49f2-93d3-a1df6a89dd35")!
    let _ = channel.observeMessageReceived(from: featureID) { _, _ in }
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let queriedFeatures = [Data(featureID.uuidString.utf8)]
    let request = createSystemQuery(
      type: SystemQueryType.isFeatureSupported, payloads: queriedFeatures)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedStatus = FeatureSupportStatus.with {
      $0.featureID = featureID.uuidString
      $0.isSupported = true
    }
    let expectedFeatureSupportResponse = FeatureSupportResponse.with {
      $0.statuses = [expectedStatus]
    }
    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try! expectedFeatureSupportResponse.serializedData()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testFeatureSupportStatus_unsupportedFeature_sendsUnsupportedStatus() {
    // This feature ID is not registered in the channel, thus considered unavailable/unsupported.
    let unsupportedFeatureID = UUID(uuidString: "032cfe53-837d-4ab9-acd6-d9488347f647")!
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let queriedFeatures = [Data(unsupportedFeatureID.uuidString.utf8)]
    let request = createSystemQuery(
      type: SystemQueryType.isFeatureSupported, payloads: queriedFeatures)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedStatus = FeatureSupportStatus.with {
      $0.featureID = unsupportedFeatureID.uuidString
      $0.isSupported = false
    }
    let expectedFeatureSupportResponse = FeatureSupportResponse.with {
      $0.statuses = [expectedStatus]
    }
    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try! expectedFeatureSupportResponse.serializedData()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testFeatureSupportStatus_invalidFeatureID_ignored() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let queriedFeatures = [Data("invalid-uuid-value".utf8)]
    let request = createSystemQuery(
      type: SystemQueryType.isFeatureSupported, payloads: queriedFeatures)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    // Empty list of support status because the invalid feature ID should be ignored.
    let expectedFeatureSupportResponse = FeatureSupportResponse.with {
      $0.statuses = []
    }
    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try! expectedFeatureSupportResponse.serializedData()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testFeatureSupportStatus_mixedSupportedFeatures_sendsStatus() {
    // This feature ID is not registered in the channel, thus considered unavailable/unsupported.
    let unsupportedFeatureID = UUID(uuidString: "032cfe53-837d-4ab9-acd6-d9488347f647")!
    let supportedFeatureID = UUID(uuidString: "dbca154b-f9c8-49f2-93d3-a1df6a89dd35")!
    let _ = channel.observeMessageReceived(from: supportedFeatureID) { _, _ in }
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    let queriedFeatures = [
      Data(unsupportedFeatureID.uuidString.utf8), Data(supportedFeatureID.uuidString.utf8),
    ]
    let request = createSystemQuery(
      type: SystemQueryType.isFeatureSupported, payloads: queriedFeatures)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedUnsupportedStatus = FeatureSupportStatus.with {
      $0.featureID = unsupportedFeatureID.uuidString
      $0.isSupported = false
    }
    let expectedSupportedStatus = FeatureSupportStatus.with {
      $0.featureID = supportedFeatureID.uuidString
      $0.isSupported = true
    }
    let expectedFeatureSupportResponse = FeatureSupportResponse.with {
      $0.statuses = [expectedUnsupportedStatus, expectedSupportedStatus]
    }
    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: true,
      response: try! expectedFeatureSupportResponse.serializedData()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  // MARK: - Error path tests

  func testQueryWithInvalidType_sendsUnsuccessfulQueryResponse() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Create a query with the wrong type.
    let request = createSystemQuery(type: SystemQueryType.unknown)
    let query = Query(request: request, parameters: nil)
    let queryID: Int32 = 13
    channel.triggerQuery(query, queryID: queryID, from: SystemFeatureManager.recipientUUID)

    let expectedQueryResponse = QueryResponse(
      id: queryID,
      isSuccessful: false,
      response: Data()
    )
    XCTAssertEqual(channel.writtenQueryResponses.count, 1)
    XCTAssertEqual(channel.writtenQueryResponses[0].queryResponse, expectedQueryResponse)
  }

  func testInvalidQueryProto_doesNotSendQueryResponse() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    // Query with an invalid `request` field.
    let query = Query(request: Data("fake proto".utf8), parameters: nil)
    channel.triggerQuery(query, queryID: 13, from: SystemFeatureManager.recipientUUID)

    XCTAssertTrue(channel.writtenQueryResponses.isEmpty)
    XCTAssertTrue(channel.writtenMessages.isEmpty)
  }

  func testOnMessageReceived_doesNotSendQueryResponse() {
    connectedCarManagerMock.triggerSecureChannelSetUp(with: channel)

    channel.triggerMessageReceived(Data("message".utf8), from: SystemFeatureManager.recipientUUID)

    XCTAssertTrue(channel.writtenQueryResponses.isEmpty)
    XCTAssertTrue(channel.writtenMessages.isEmpty)
  }

  // MARK: - Helper methods

  /// Returns a serialized `SystemQuery` proto that has its type set to the given value.
  private func createSystemQuery(type: SystemQueryType, payloads: [Data] = []) -> Data {
    var systemQuery = SystemQuery()
    systemQuery.type = type
    systemQuery.payloads = payloads
    return try! systemQuery.serializedData()
  }
}

/// A fake device that will return the name it is initialized with.
struct FakeDevice: AnyDevice {
  let name: String
  let model = "model"
  let localizedModel = "localizedModel"
  let systemName = "systemName"
  let systemVersion = "systemVersion"
  let batteryLevel: Float = 100

  init(name: String) {
    self.name = name
  }
}

/// A fake `AppNameProvider` that returns the app name it was initialized with.
struct FakeAppNameProvider: AppNameProvider {
  let appName: String?
}
