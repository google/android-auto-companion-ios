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

@_implementationOnly import AndroidAutoCoreBluetoothProtocols
@_implementationOnly import AndroidAutoMessageStream
@_implementationOnly import AndroidAutoSecureChannel
import CoreBluetooth
import Foundation

/// Protocol to be adopted by factories which make message exchange helpers.
protocol AssociationMessageHelperFactory {
  @MainActor func makeHelper(
    associator: Associator,
    securityVersion: MessageSecurityVersion,
    messageStream: MessageStream
  ) -> AssociationMessageHelper
}

/// The default factory for making message exchange helpers.
struct AssociationMessageHelperFactoryImpl: AssociationMessageHelperFactory {
  func makeHelper(
    associator: Associator,
    securityVersion: MessageSecurityVersion,
    messageStream: MessageStream
  ) -> AssociationMessageHelper {
    // See go/aae-batmobile-versioning for details on the security versions.
    switch securityVersion {
    case .v1:
      return AssociationMessageHelperV1(associator, messageStream: messageStream)
    case .v2, .v3:
      return AssociationMessageHelperV2(associator, messageStream: messageStream)
    case .v4:
      return AssociationMessageHelperV4(associator, messageStream: messageStream)
    }
  }
}
