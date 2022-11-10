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

#import "AAEUKey2Wrapper.h"
#import <os/log.h>

#include "security/cryptauth/lib/securegcm/ukey2_handshake.h"

/**
 * Utility method that will transform a C++ string to an |NSData| object that is usable by
 * Objective-C. This method should be used to transform encrypted strings to a format that can be
 * manipulated by this wrapper.
 *
 * @param str A pointer to the string to transform.
 * @return The wrapped string or |nil| if the pointer is invalid.
 */
static NSData *DataFromString(const std::unique_ptr<string> &str) {
  return str ? [NSData dataWithBytes:str->data() length:str->length()] : nil;
}

/**
 * Utility method to transform a data object back back into a C++ string. The data object should
 * be one that was created by |DataFromString|.
 *
 * @param data The data to unwrap.
 * @return The corresponding |std::string|.
 */
static string CPPStringFromData(const NSData *data) {
  return string(static_cast<const char *>([data bytes]), [data length]);
}

#define CREATE_UKEY2_LOGGER() os_log_create("AndroidAutoUKey2Wrapper", "AAEUKey2Wrapper")

@interface AAEUKey2Wrapper ()
@property(nonnull, nonatomic, readonly) os_log_t logger;
@end

@implementation AAEUKey2Wrapper {
  std::unique_ptr<securegcm::UKey2Handshake> _handshake;
  std::unique_ptr<securegcm::D2DConnectionContextV1> _context;
}

- (nullable instancetype)initWithSavedSession:(NSData *)savedSession {
  self = [super init];

  if (!self) {
    return nil;
  }

  _logger = CREATE_UKEY2_LOGGER();
  _context = securegcm::D2DConnectionContextV1::FromSavedSession(CPPStringFromData(savedSession));

  if (!_context) {
    return nil;
  }

  return self;
}

- (instancetype)initWithRole:(AAERole)role {
  self = [super init];
  if (self) {
    _logger = CREATE_UKEY2_LOGGER();

    if (role == AAERoleResponder) {
      _handshake = securegcm::UKey2Handshake::ForResponder(
          securegcm::UKey2Handshake::HandshakeCipher::P256_SHA512);
    } else {
      _handshake = securegcm::UKey2Handshake::ForInitiator(
          securegcm::UKey2Handshake::HandshakeCipher::P256_SHA512);
    }
  }

  return self;
}

// MARK: - Properties.

- (AAEState)handshakeState {
  // If the handshake has been null-ed out, that means the handshake was completed. So return
  // the state indicating as such.
  if (!_handshake) {
    return AAEStateAlreadyUsed;
  }

  switch (_handshake->GetHandshakeState()) {
    case securegcm::UKey2Handshake::State::kInProgress:
      return AAEStateInProgress;
    case securegcm::UKey2Handshake::State::kVerificationNeeded:
      return AAEStateVerificationNeeded;
    case securegcm::UKey2Handshake::State::kVerificationInProgress:
      return AAEStateVerificationInProgress;
    case securegcm::UKey2Handshake::State::kFinished:
      return AAEStateFinished;
    case securegcm::UKey2Handshake::State::kAlreadyUsed:
      return AAEStateAlreadyUsed;
    case securegcm::UKey2Handshake::State::kError:
    default:
      return AAEStateError;
  }
}

- (NSString *)lastHandshakeError {
  if (!_handshake) {
    return @"";
  }

  return [NSString stringWithUTF8String:_handshake->GetLastError().c_str()];
}

- (NSData *)uniqueSessionKey {
  if (![self ensureConnectionContext]) {
    return nil;
  }

  return DataFromString(_context->GetSessionUnique());
}

// MARK: - Public Methods.

- (NSData *)nextHandshakeMessage {
  if (!_handshake) {
    return nil;
  }

  return DataFromString(_handshake->GetNextHandshakeMessage());
}

- (AAEParseResult *)parseHandshakeMessage:(NSData *)handshakeMessage {
  if (!_handshake) {
    return [[AAEParseResult alloc] initWithSuccess:NO alertToSend:nil];
  }

  securegcm::UKey2Handshake::ParseResult result =
      _handshake->ParseHandshakeMessage(CPPStringFromData(handshakeMessage));

  BOOL isSuccessful = result.success ? YES : NO;
  NSData *alertToSend = DataFromString(result.alert_to_send);

  return [[AAEParseResult alloc] initWithSuccess:isSuccessful alertToSend:alertToSend];
}

- (NSData *)verificationDataWithByteLength:(NSInteger)byteLength {
  if (!_handshake) {
    return nil;
  }

  return DataFromString(_handshake->GetVerificationString((int)byteLength));
}

- (BOOL)verifyHandshake {
  if (!_handshake || !_handshake->VerifyHandshake()) {
    return NO;
  }

  return YES;
}

- (NSData *)encodeMessage:(NSData *)message {
  if (![self ensureConnectionContext]) {
    os_log_error(self.logger, "Message encoding failed due to missing connection context.");
    return nil;
  }

  return DataFromString(_context->EncodeMessageToPeer(CPPStringFromData(message)));
}

- (NSData *)decodeMessage:(NSData *)message {
  if (![self ensureConnectionContext]) {
    os_log_error(self.logger, "Message decoding failed due to missing connection context.");
    return nil;
  }

  string rawMessage = CPPStringFromData(message);
  std::unique_ptr<std::string> decodedMessage = _context->DecodeMessageFromPeer(rawMessage);
  if (decodedMessage) {
    return DataFromString(decodedMessage);
  } else {
    NSString *reason = [self lastHandshakeError];
    if (reason && [reason length] > 0) {
      os_log_error(self.logger, "Message decoding failed with handshake error: %@", reason);
    } else {
      os_log_error(self.logger, "Message decoding failed.");
    }
    return nil;
  }
}

- (NSData *)saveSession {
  if (![self ensureConnectionContext]) {
    os_log_error(self.logger, "Saving session failed due to missing connection context.");
    return nil;
  }

  return DataFromString(_context->SaveSession());
}

// MARK: - Private Methods.

/**
 * Ensures that the |_context| variable is properly set. This method should be called before any of
 * the encoding and decoding message methods can be used.
 *
 * This method should only be called when the state returned by |getHandshakeState| is
 * |StateWrapper.FINISHED|. But if it's called before then, then it will produce an error message
 * that can be retrieved off of |getLastError|.
 *
 * @return YES if the |_context| was properly set up.
 */
- (BOOL)ensureConnectionContext {
  if (_context) {
    return YES;
  }

  _context = _handshake->ToConnectionContext();

  // Switching to context mode, so null out the _handshake so no more handshake methods can be
  // used.
  if (_context) {
    _handshake = nullptr;
    return YES;
  }

  return NO;
}

@end
