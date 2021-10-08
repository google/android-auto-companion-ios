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

#import "AAEParseResult.h"

NS_ASSUME_NONNULL_BEGIN

/** The possible roles that this wrapper can take. */
typedef NS_ENUM(NSInteger, AAERole) {
  /**
   * The responder acts as a server. The responder should  wait to receive the first message.
   */
  AAERoleResponder,

  /**
   * The initiator is the client. The initiator should begin the handshake.
   */
  AAERoleInitiator,
};

/** The possible states of a handshake. */
typedef NS_ENUM(NSInteger, AAEState) {
  /**
   * A handshake is in progress. The caller should use |nextHandshakeMessage| and
   * |parseHandshakeMessage| to continue the handshake.
   */
  AAEStateInProgress,

  /**
   * The handshake is completed, but pending verification of the authentication string. Clients
   * should use |verificationDataWithByteLength| to get the verification string and use
   * out-of-band methods to authenticate the handshake.
   */
  AAEStateVerificationNeeded,

  /**
   * The handshake is complete and the verification string has been generated but not confirmed.
   * After authenticating the handshake out-of-band, use |verifyHandshake| to mark the handshake
   * as verified.
   */
  AAEStateVerificationInProgress,

  /**
   * The handshake is finished, and the caller can begin to use encoding and decoding message
   * methods.
   */
  AAEStateFinished,

  /** The handshake has already been used and no more handshake methods should be used. */
  AAEStateAlreadyUsed,

  /** There was an error during the handshake process and should not be used anymore. */
  AAEStateError,
};

/**
 * An Objective-C wrapper around UKEY2 so that it can be used in Swift or Objective-C files. There
 * is currently only one |HandshakeCipher| that UKey2 can be initialized with. As a result, to use
 * this wrapper, just create an instance of it. It will automatically use the P256_SHA512 cipher.
 *
 * This wrapper also combines the functionality of the |securegcm::UKey2Handshake| and
 * |securegcm::D2DConnectionContextV1|. Exposing |D2DConnectionContextV1| with its own wrapper
 * would require wrapping |securemessage::CryptoOps::SecretKey| and all its dependencies -- this is
 * not very scalable.
 *
 * As a result, hide the details of |D2DConnectionContextV1| within this wrapper.
 */
NS_SWIFT_NAME(UKey2Wrapper)
@interface AAEUKey2Wrapper : NSObject

/**
 * The current state of the handshake.
 */
@property(nonatomic, readonly) AAEState handshakeState;

/**
 * The last error message pertaining to the handshake. If there is no error, then this value is
 * an empty string.
 */
@property(nonatomic, readonly) NSString *lastHandshakeError;

/**
 * A key that can be used to unique identify the current session.
 *
 * The key is a cryptographic digest (SHA256) of the session keys prepended by the SHA256 hash of
 * the ASCII string "D2D".
 *
 * This property will only be valid after |handshakeState| is |StateWrapper.FINISHED|.
 */
@property(nonatomic, readonly, nullable) NSData *uniqueSessionKey;

/**
 * Creates a wrapper based on the given saved session.
 *
 * The session passed to this method should be one returned by |saveSession|. If the given session
 * is not valid, then |nil| will be returned.
 *
 * Note, that the created wrapper will have its handshake state already valid. So, the
 * |encodeMessage| and |decodeMessage| methods will be ready to use.
 *
 * @param savedSession An encoded session returned by |saveSession|.
 * @return A valid wrapper or |nil| if there is an error parsing the session information.
 */
- (nullable instancetype)initWithSavedSession:(NSData *)savedSession;

/**
 * Creates this wrapper to act as the given role.
 *
 * @param role The role that this wrapper will take on.
 */
- (instancetype)initWithRole:(AAERole)role;

/**
 * The next handshake message suitable for sending on the wire. If |nil| is returned, then check
 * |lastHandshakeError| for the error message.
 *
 * @return The next handshake message of |nil| if there is an error.
 */
- (nullable NSData *)nextHandshakeMessage;

/**
 * Parses the given handshake message. This method will update the internal state of the handshake
 * based on the value of the message.
 *
 * If there was an error with the parse, check |lastHandshakeError| for the error message.
 *
 * @param handshakeMessage The message to parse.
 * @return A wrapper that holds the result of the parse.
 */
- (AAEParseResult *)parseHandshakeMessage:(NSData *)handshakeMessage;

/**
 * Returns authentication data suitable for authenticating the handshake out-of-band. This data
 * can be used to generate a display string off of.
 *
 * This method should only be called when the state returned from |handshakeState| is
 * |StateWrapper.VERIFICATION_NEEDED|, meaning this method can only be called once.
 *
 * @param byteLength The length of the output. The minimum length is 1, and the maximum
 *                   length is 32.
 * @return The authentication data or |nil| if there was an error.
 */
- (nullable NSData *)verificationDataWithByteLength:(NSInteger)byteLength;

/**
 * Invoke to let the handshake state machine know that the caller has validated the authentication
 * string obtained via |verificationDataWithByteLength|.
 *
 * Note: This should only be called when the state returned by |handshakeState| is
 * |StateWrapper.VERIFICATION_IN_PROGRESS|.
 *
 * @return YES if the state machine is able to acknowledge the verification. If NO is returned,
 * check |lastHandshakeError| for the error message.
 */
- (BOOL)verifyHandshake;

/**
 * Encrypts and signs the given message.
 *
 * This method should only be called after |handshakeState| returns |StateWrapper.FINISHED|.
 *
 * @param message The message to encode as bytes stored within |NSData|.
 * @return The encoded message or |nil| if there was an error.
 */
- (nullable NSData *)encodeMessage:(NSData *)message NS_SWIFT_NAME(encode(_:));

/**
 * Decodes and verifies the given message.
 *
 * This method should only be called after |handshakeState| returns |StateWrapper.FINISHED|.
 *
 * @param message The message to decode.
 * @return The decoded message or |nil| if there was an error.
 */
- (nullable NSData *)decodeMessage:(NSData *)message NS_SWIFT_NAME(decode(_:));

/**
 * Returns a data object that can be used to recreate the current session.
 *
 * This method is only valid after a secure session has been established. That is, |handshakeState|
 * should return |StateWrapper.FINISHED|.
 *
 * @return An encoded version of the current session or |nil| if a session has not been established.
 */
- (nullable NSData *)saveSession;

@end

NS_ASSUME_NONNULL_END
