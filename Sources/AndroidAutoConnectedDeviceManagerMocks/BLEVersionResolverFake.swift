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
import Foundation

/// Fake `BLEVersionResolver` that will always resolve to the `.passthrough` stream version
///  and the configurable security version.
public class BLEVersionResolverFake: NSObject, BLEVersionResolver {
  // MARK: - Configuration
  public var securityVersion = MessageSecurityVersion.v1

  // MARK: - BLEVersionResolver

  public weak var delegate: BLEVersionResolverDelegate?

  public func resolveVersion(
    with peripheral: BLEPeripheral,
    readCharacteristic: BLECharacteristic,
    writeCharacteristic: BLECharacteristic,
    allowsCapabilitiesExchange: Bool
  ) {
    delegate?.bleVersionResolver(
      self,
      didResolveStreamVersionTo: .passthrough,
      securityVersionTo: securityVersion,
      for: peripheral
    )
  }
}
