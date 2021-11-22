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
import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager

private typealias SystemQuery = Com_Google_Companionprotos_SystemQuery
private typealias SystemQueryType = Com_Google_Companionprotos_SystemQueryType
private typealias SystemUserRoleResponse = Com_Google_Companionprotos_SystemUserRoleResponse
typealias SystemUserRole = Com_Google_Companionprotos_SystemUserRole

/// Unit tests for `SystemFeatureManager`.
class SystemFeatureManagerTest: XCTestCase {
  private let deviceName = "DeviceName"
  private let appName = "appName"
  private var car: Car!

  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var channel: SecuredCarChannelMock!
  private var manager: SystemFeatureManager!

  override func setUp() {
    super.setUp()
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
    XCTAssertEqual(channel.writtenQueryResponses[0], expectedQueryResponse)
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
    XCTAssertEqual(channel.writtenQueryResponses[0], expectedQueryResponse)
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
    XCTAssertEqual(channel.writtenQueryResponses[0], expectedQueryResponse)
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
    XCTAssertEqual(channel.writtenQueryResponses[0], expectedQueryResponse)
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
  private func createSystemQuery(type: SystemQueryType) -> Data {
    var systemQuery = SystemQuery()
    systemQuery.type = type
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
