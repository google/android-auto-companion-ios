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
@_implementationOnly import AndroidAutoCompanionProtos

private typealias OutOfBandAssociationToken = Com_Google_Companionprotos_OutOfBandAssociationToken

#if canImport(CryptoKit)
  import CryptoKit

  /// Extensions for CryptoKit.
  extension OutOfBandAssociationToken {
    /// Nonce used for decrypting a message.
    private var decryptionNonce: AES.GCM.Nonce? {
      try? AES.GCM.Nonce(data: ihuIv)
    }

    /// Nonce used for encrypting a message.
    private var encryptionNonce: AES.GCM.Nonce? {
      try? AES.GCM.Nonce(data: mobileIv)
    }

    /// Cypher AES key used for encryption.
    private var cipherKey: SymmetricKey {
      SymmetricKey(data: encryptionKey)
    }
  }

  /// OutOfBandToken Conformance.
  extension OutOfBandAssociationToken: OutOfBandToken {
    /// Size of the authentication tag appended to the end of the encrypted data.
    private static let tagSize = 16

    func encrypt(_ message: Data) throws -> Data {
      guard let encryptionNonce = encryptionNonce else {
        throw OutOfBandTokenError.invalidNonce
      }

      let sealedBox = try AES.GCM.seal(message, using: cipherKey, nonce: encryptionNonce)
      return sealedBox.ciphertext + sealedBox.tag
    }

    func decrypt(_ message: Data) throws -> Data {
      guard let decryptionNonce = decryptionNonce else {
        throw OutOfBandTokenError.invalidNonce
      }

      guard message.count >= Self.tagSize else {
        throw OutOfBandTokenError.invalidDataSize(message.count)
      }

      let cipherTextSize = message.count - Self.tagSize
      let cipherText = message[0..<cipherTextSize]
      let tag = message[cipherTextSize..<message.count]

      let box = try AES.GCM.SealedBox(nonce: decryptionNonce, ciphertext: cipherText, tag: tag)
      return try AES.GCM.open(box, using: cipherKey)
    }
  }
#endif
