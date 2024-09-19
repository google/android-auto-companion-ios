// Copyright 2024 Google LLC
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

private import AndroidAutoConnectedDeviceManager
private import AndroidAutoConnectedDeviceManagerMocks
internal import XCTest

@testable private import AndroidAutoAccountTransfer

class AccountTransferManagerTest: XCTestCase {
  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var channelMock: SecuredCarChannelMock!

  private var accountTransferManager: AccountTransferManager!

  override func setUp() async throws {
    try await super.setUp()
    continueAfterFailure = false

    await setUpOnMain()
  }

  @MainActor private func setUpOnMain() {
    connectedCarManagerMock = ConnectedCarManagerMock()
    channelMock = SecuredCarChannelMock(id: "id", name: "mock")
    accountTransferManager = AccountTransferManager(connectedCarManager: connectedCarManagerMock)
  }

  @MainActor func testIgnoreMalformedMessage() {
    let car = Car(id: "id", name: "mock")

    connectedCarManagerMock.triggerSecureChannelSetUp(with: channelMock)
    connectedCarManagerMock.triggerConnection(for: car)
    accountTransferManager.onMessageReceived(Data(), from: car)

    XCTAssertEqual(channelMock.writtenMessages.count, 0)
  }
}
