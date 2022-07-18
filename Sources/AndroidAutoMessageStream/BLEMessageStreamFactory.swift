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

/// Creator of different message streams.
public enum BLEMessageStreamFactory {
  /// Creates a message stream of the given version.
  ///
  /// - Parameters:
  ///   - version: The version of the stream to create.
  ///   - peripheral: The peripheral to stream messages with.
  ///   - readCharacteristic: The characteristic on the peripheral to read messages from.
  ///   - writeCharacteristic: The characteristic on the peripheral to write messages to.
  ///   - allowsCompression: Whether the caller allows compression if supported.
  /// - Returns: An appropriate `BLEMessageStream`.
  public static func makeStream(
    version: MessageStreamVersion,
    peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic,
    allowsCompression: Bool
  ) -> BLEMessageStream {
    switch version {
    case .passthrough:
      return BLEMessageStreamPassthrough(
        peripheral: peripheral,
        readCharacteristic: readCharacteristic,
        writeCharacteristic: writeCharacteristic
      )
    case .v2(let peripheralSupportsCompression):
      let isCompressionEnabled = allowsCompression && peripheralSupportsCompression
      return BLEMessageStreamV2(
        peripheral: peripheral,
        readCharacteristic: readCharacteristic,
        writeCharacteristic: writeCharacteristic,
        messageCompressor: DataCompressorImpl.zlib,
        isCompressionEnabled: isCompressionEnabled
      )
    }
  }
}
