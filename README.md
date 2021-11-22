# Android Auto Companion Library

Library that will abstract away the process of associating a phone with an
Android Auto head unit. Once associated, a device will gain the ability to
unlock the head unit via BLE.

## AndroidAutoConnectedDeviceManager

The main library that supplies the ability to associate and connect to an
Android Auto vehicle. Full usage instructions, can be found on the
[Phone SDK Integration Guide](https://docs.partner.android.com/gas/integrate/companion_app/cd_phone_sdk).

### AndroidAutoUKey2Wrapper

This helper library wraps the [ukey2](https://github.com/google/ukey2) library.
It is included as a prebuilt `.xcframework` file in order to allow for
easier compilation via Swift Package Manager.

## Message Stream Module

Helper library for chunking data to be sent over BLE. BLE defines a maximum
size that can be sent at one time (known as the MTU size). In order to send
messages that are larger than this, the data needs to be split into packets
equal to the MTU size or less and reassembled by the other device.

## Logging Module

The logging module provides general logging capabilities with an API that is
designed for Swift.

The Logger struct is the main interface for configuration and logging.

### Usage

When the logger is initialized, the subsystem is inferred from the calling
context, and the category is derived from the type and the subsystem.

```swift
let logger = Logger(for: TestType.self)
```

It follows the modifier pattern in which a logger instance is immutable from
the public API, and a modifier can configure and return a new logger. The
most common property that can be configured this way is the level.

```swift
logger.info.log("Test")
```

The log record may contain information to be redacted when persisted as such:

```swift
logger.info.log("Test for id:", redacting: "abc123")
```

In Swift 5.2 and later, the `log()` method can be left off since logging is
intrinsic to what the lagger does:

```swift
logger.info("Test")
```

#### Levels in order of increasing significance.

Level    | Effect
-------- | -------------------------------------------------------------
debug    | In memory logging only.
info     | Low importance. May get pruned from logs.
standard | Default logging level.
error    | Suitable for logging recoverable errors.
fault    | Suitable for logging programming errors. Provides backtraces.

