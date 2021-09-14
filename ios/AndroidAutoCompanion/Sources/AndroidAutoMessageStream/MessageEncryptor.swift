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

/// An encryptor that will be used by a `BLEMessageStream` to encrypt and decrypt messages.
public protocol MessageEncryptor {
  /// Encrypts the given message for sending.
  ///
  /// - Return: The encrypted message.
  /// - Throws: An error if the message cannot be encrypted.
  func encrypt(_ message: Data) throws -> Data

  /// Decrypts the given message that has been sent by a BLE peripheral.
  ///
  /// - Return: The decrypted message.
  /// - Throws: An error if the message cannot be decrypted.
  func decrypt(_ message: Data) throws -> Data
}
