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

#import "AAECryptoOps.h"

#include "third_party/securemessage/include/securemessage/crypto_ops.h"

/**
 * Utility method that will transform a C++ string to an |NSData| object that is usable by
 * Objective-C.
 *
 * @param str A pointer to the string to transform.
 * @return The wrapped string or |nil| if the pointer is invalid.
 */
static NSData *DataFromString(const std::unique_ptr<string> &str) {
  return str ? [NSData dataWithBytes:str->data() length:str->length()] : nil;
}

/**
 * Utility method to transform a data object back into a C++ string.
 *
 * @param data The data to unwrap.
 * @return The corresponding |std::string|.
 */
static string CPPStringFromData(const NSData *data) {
  return string(static_cast<const char *>([data bytes]), [data length]);
}

@implementation AAECryptoOps

+ (NSData *)hkdfWithInputKeyMaterial:(NSData *)inputKeyMaterial
                                salt:(NSData *)salt
                                info:(NSData *)info {
  std::unique_ptr<string> hkdf = securemessage::CryptoOps::Hkdf(
      CPPStringFromData(inputKeyMaterial), CPPStringFromData(salt), CPPStringFromData(info));

  return DataFromString(hkdf);
}

@end
