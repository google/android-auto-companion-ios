// Copyright 2023 Google LLC
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

import AndroidAutoLogger
import Foundation
import SwiftProtobuf
@_implementationOnly import AndroidAutoConnectionHowitzerV2Protos

typealias HowitzerMessageProto =
  Com_Google_Android_Connecteddevice_Connectionhowitzer_Proto_HowitzerMessage
typealias HowitzerConfigProto = Com_Google_Android_Connecteddevice_Connectionhowitzer_Proto_Config
typealias HowitzerResultProto = Com_Google_Android_Connecteddevice_Connectionhowitzer_Proto_Result
typealias Timestamp = Google_Protobuf_Timestamp

extension HowitzerMessageProto {
  /// Initialzer for ack message.
  init(type: HowitzerMessageProto.MessageType) {
    self.init()

    self.messageType = type
  }

  /// Initializer for config message.
  init(testID: UUID, config: HowitzerConfig) {
    self.init()

    self.messageType = .config
    self.config = HowitzerConfigProto(testID: testID, config: config)
  }

  /// Initializer for result message.
  init(
    testID: UUID,
    config: HowitzerConfig,
    result: HowitzerResult
  ) {
    self.init()

    self.messageType = .result
    self.config = HowitzerConfigProto(testID: testID, config: config)
    self.result = HowitzerResultProto(result: result)
  }
}

extension HowitzerConfigProto {
  init(testID: UUID, config: HowitzerConfig) {
    self.init()

    self.testID = testID.uuidString.lowercased()
    self.payloadSize = config.payloadSize
    self.payloadCount = config.payloadCount
    self.sendPayloadFromIhu = config.sentFromIHU
  }
}

extension HowitzerResultProto {
  init(result: HowitzerResult) {
    self.init()

    self.isValid = result.isValid
    self.payloadReceivedTimestamps = result.payloadReceivedTimestamps.map {
      Timestamp(timeIntervalSince1970: $0)
    }
    self.testStartTimestamp = Timestamp(timeIntervalSince1970: result.testStartTime)
  }
}
