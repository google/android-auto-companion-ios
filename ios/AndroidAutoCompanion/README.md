# Android Auto Companion Library

Library that will abstract away the process of associating a phone with an
Android Auto head unit. Once associated, a device will gain the ability to
unlock the head unit via BLE.

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

The logger is initialized with a subsystem and category:

```swift
let logger = Logger(
  subsystem: "TestSystem",
  category: "TestCat")
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
