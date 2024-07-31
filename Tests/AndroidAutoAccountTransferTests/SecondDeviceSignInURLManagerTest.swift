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
private import UIKit
internal import XCTest

@testable private import AndroidAutoAccountTransfer

class SecondDeviceSignInURLManagerTest: XCTestCase {
  private let validURL = "https://accounts.google.com/signin/continue"

  private var connectedCarManagerMock: ConnectedCarManagerMock!
  private var channelMock: SecuredCarChannelMock!

  private var secondDeviceSignInURLManager: SecondDeviceSignInURLManager!

  @MainActor override func setUp() {
    super.setUp()
    continueAfterFailure = false
    connectedCarManagerMock = ConnectedCarManagerMock()
    channelMock = SecuredCarChannelMock(id: "id", name: "mock")

    secondDeviceSignInURLManager = SecondDeviceSignInURLManager(
      connectedCarManager: connectedCarManagerMock)
  }

  @MainActor func testOnMessageReceived_ignoreNonSignInTypeMessage() {
    let car = Car(id: "id", name: "mock")

    secondDeviceSignInURLManager.onMessageReceived(Data(), from: car)

    XCTAssertEqual(channelMock.writtenMessages.count, 0)
  }

  @MainActor func testStartSignIn_noURL_ignored() {
    let mockUIViewController = MockUIViewController()

    XCTAssertFalse(secondDeviceSignInURLManager.startSignIn(from: mockUIViewController))
    XCTAssertNil(mockUIViewController.presentedController)
  }
}

private class MockUIViewController: UIViewController {
  var presentedController: UIViewController? = nil

  override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)?) {
    presentedController = controller
  }
}
