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

import Foundation
import XCTest
@_implementationOnly import AndroidAutoCompanionProtos

@testable import AndroidAutoConnectedDeviceManager

private typealias OutOfBandAssociationData = Com_Google_Companionprotos_OutOfBandAssociationData
private typealias OutOfBandAssociationToken = Com_Google_Companionprotos_OutOfBandAssociationToken

/// Unit tests for OutOfBandAssociationDataSource.
@available(watchOS 6.0, *)
class OutOfBandAssociationDataSourceTest: XCTestCase {
  func testURLMissingQueryThrows() {
    let url = URL(string: "http://companion/associate")
    XCTAssertThrowsError(try OutOfBandAssociationDataSource(url!))
  }

  func testURLMissingOutOfBandDataThrows() {
    let url = URL(string: "http://companion/associate?xyz=123")
    XCTAssertThrowsError(try OutOfBandAssociationDataSource(url!))
  }

  func testExtractsOutOfBandDataFromURL() throws {
    // Create a fake token.
    var token = OutOfBandAssociationToken()
    token.encryptionKey = Data("key".utf8)
    token.ihuIv = Data("ihuIv".utf8)
    token.mobileIv = Data("mobileIv".utf8)

    var outOfBandData = OutOfBandAssociationData()
    outOfBandData.token = token
    outOfBandData.deviceIdentifier = Data(hex: "A1B2")!

    let querySafeBase64 = try outOfBandData.serializedData().base64EncodedString()
      .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")

    let url = URL(string: "http://companion/associate?oobData=\(querySafeBase64)")

    let dataSource = try OutOfBandAssociationDataSource(url!)

    XCTAssertEqual(dataSource.deviceID.hex, "A1B2")
    XCTAssertTrue(dataSource.token is OutOfBandAssociationToken)
    XCTAssertEqual(dataSource.token as! OutOfBandAssociationToken, token)
  }
}
