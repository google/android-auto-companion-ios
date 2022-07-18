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

import AndroidAutoCoreBluetoothProtocols
import AndroidAutoMessageStream
import AndroidAutoSecureChannel

@testable import AndroidAutoConnectedDeviceManager

/// The fake factory for making message exchange helper mocks.
public struct AssociationMessageHelperFactoryFake: AssociationMessageHelperFactory {
  public init() {}

  public func makeHelper(
    associator: Associator,
    securityVersion: MessageSecurityVersion,
    messageStream: MessageStream
  ) -> AssociationMessageHelper {
    return AssociationMessageHelperMock(
      associator, messageStream: messageStream)
  }
}

/// Proxy for a `AssociationMessageHelperFactory` so we can set the internal behavior.
public class AssociationMessageHelperFactoryProxy: AssociationMessageHelperFactory {
  public var shouldUseRealFactory = false
  public var latestMessageHelper: AssociationMessageHelper?

  public init() {}

  public func reset() {
    shouldUseRealFactory = false
    latestMessageHelper = nil
  }

  public func makeHelper(
    associator: Associator,
    securityVersion: MessageSecurityVersion,
    messageStream: MessageStream
  ) -> AssociationMessageHelper {
    let factory: AssociationMessageHelperFactory
    if shouldUseRealFactory {
      factory = AssociationMessageHelperFactoryImpl()
    } else {
      factory = AssociationMessageHelperFactoryFake()
    }
    let messageHelper = factory.makeHelper(
      associator: associator, securityVersion: securityVersion, messageStream: messageStream)
    latestMessageHelper = messageHelper
    return messageHelper
  }
}
