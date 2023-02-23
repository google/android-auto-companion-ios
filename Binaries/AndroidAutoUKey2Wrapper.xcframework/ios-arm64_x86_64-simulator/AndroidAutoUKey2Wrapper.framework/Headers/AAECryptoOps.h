/*
 * Copyright 2021 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** Encapsulates utility cryptographic operations used by UKey2 classes. */
NS_SWIFT_NAME(CryptoOps)
@interface AAECryptoOps : NSObject

/**
 * Implements HKDF (RFC 5869) with the SHA-256 hash and a 256-bit output key length.
 *
 * @param inputKeyMaterial Master key from which to derive sub-keys.
 * @param salt A (public) randomly generated 256-bit input that can be re-used.
 * @param info Arbitrary information that is bound to the derived key (i.e. used in its
 *             creation).
 * @return The derived key bytes = HKDF-SHA256(inputKeyMaterial, salt, info) on success or |nil|
 *     on error.
 */
+ (nullable NSData *)hkdfWithInputKeyMaterial:(NSData *)inputKeyMaterial
                                         salt:(NSData *)salt
                                         info:(NSData *)info
    NS_SWIFT_NAME(hkdf(inputKeyMaterial:salt:info:));

@end

NS_ASSUME_NONNULL_END
