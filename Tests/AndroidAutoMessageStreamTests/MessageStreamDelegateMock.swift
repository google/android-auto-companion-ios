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
import Foundation

@testable import AndroidAutoMessageStream

/// Allows for verification of method invocations within a `MessageStreamDelegate`.
class MessageStreamDelegateMock: NSObject, MessageStreamDelegate {
  var didUpdateValueCalledCount = 0
  var updatedMessage: Data?
  var receivedMessageParams: MessageStreamParams?

  var didEncounterWriteErrorCount = 0

  var didWriteMessageCalledCount = 0

  var encounteredUnrecoverableErrorCalled = false

  func messageStream(
    _ messageStream: MessageStream,
    didReceiveMessage message: Data,
    params: MessageStreamParams
  ) {
    didUpdateValueCalledCount += 1
    updatedMessage = message
    receivedMessageParams = params
  }

  func messageStream(
    _ messageStream: MessageStream,
    didEncounterWriteError error: Error,
    to recipient: UUID
  ) {
    didEncounterWriteErrorCount += 1
  }

  func messageStreamDidWriteMessage(_ messageStream: MessageStream, to recipient: UUID) {
    didWriteMessageCalledCount += 1
  }

  func messageStreamEncounteredUnrecoverableError(_ messageStream: MessageStream) {
    encounteredUnrecoverableErrorCalled = true
  }
}
