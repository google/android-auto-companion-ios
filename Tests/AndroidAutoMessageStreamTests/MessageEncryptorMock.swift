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

import AndroidAutoMessageStream
import Foundation

/// A mock of the `MessageEncryptor`.
class MessageEncryptorMock: NSObject, MessageEncryptor {
  /// Whether or not a call to `encrypt` will succeed.
  var canEncrypt = true

  var encryptCalledCount = 0

  /// Whether or not a call to `decrypt` will succeed.
  var canDecrypt = true

  var decryptCalledCount = 0

  func encrypt(_ message: Data) throws -> Data {
    encryptCalledCount += 1

    if canEncrypt {
      return message
    }

    throw makeFakeError()
  }

  func decrypt(_ message: Data) throws -> Data {
    decryptCalledCount += 1

    if canDecrypt {
      return message
    }

    throw makeFakeError()
  }

  private func makeFakeError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}
