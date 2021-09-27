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

/**
 * Represents the result of a handshake parse.
 */
NS_SWIFT_NAME(ParseResult)
@interface AAEParseResult : NSObject

/** Whether or not a handshake parse was successful. */
@property(nonatomic, readonly, getter=isSuccessful) BOOL success;

/**
 * An alert message to send to the remote device. This value will only be set if there was
 * an error during the parse.
 */
@property(nonatomic, readonly, nullable) NSData *alertToSend;

- (instancetype)initWithSuccess:(BOOL)success alertToSend:(nullable NSData *)alertToSend;

@end

NS_ASSUME_NONNULL_END
