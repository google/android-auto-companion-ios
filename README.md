# Android Auto Companion Library

Library that abstracts away the process of associating a phone with an Android
Auto head unit. Once associated, a device will gain the ability to unlock the
head unit via BLE.

## Build Instructions

This project uses Swift Package Manager (SPM) for builds, so generally follow
the rules for building with SPM.

### Protobuf Configuration

This project includes several [protobuf](https://developers.google.com/protocol-buffers)
files. For each raw `proto` file, a corresponding Swift source file must be
generated. An included Swift Package Manager plugin is configured to generate
the required source files. The `protoc` and `protoc-gen-swift` executables are
expected to be installed (symbolic links are fine) at `/usr/local/bin`. These
tools may be installed using [Homebrew](https://github.com/Homebrew/brew).

### Reference App

Please see the [reference app](https://github.com/google/android-auto-companion-app)
for an example of a project configured to build the Companion reference app.

### Custom Build with the Android Auto Companion Library

Please see the reference app above for an example project. If you want to create
your own custom app from scratch with a Companion dependency, here are the
steps.

1. Create an Xcode Workspace for your new project.
2. Create a new iOS App project.
3. In Xcode, select your project.
4. Click on the `Package Dependencies` tab for the project.
5. Click on the `+` button to add a new dependency.
6. Type "android-auto-companion-ios" in the search field and click
`Add Package`.
7. Select the iOS target app.
8. Click on the `Build Phases` tab for the target.
9. Expand `Link Binary with Libraries`.
10. Click the `+` button to add libraries.
11. Add `libc++.tbd`.
12. Add `AndroidAutoConnectedDeviceManager`.

## Components

### AndroidAutoConnectedDeviceManager

The main library that supplies the ability to associate and connect to an
Android Auto vehicle. Full usage instructions, can be found on the
[Phone SDK Integration Guide](https://docs.partner.android.com/gas/integrate/companion_app/cd_phone_sdk).

### AndroidAutoUKey2Wrapper

This helper library wraps the [ukey2](https://github.com/google/ukey2) library.
It is included as a prebuilt `.xcframework` file to allow for easier
compilation via Swift Package Manager.

### Message Stream Module

Helper library for chunking data to be sent over BLE. BLE defines a maximum
size that can be sent at one time (known as the MTU size). In order to send
messages that are larger than this, the data needs to be split into packets
equal to the MTU size or less and reassembled by the other device.

### Logging Module

The logging module provides general logging capabilities with an API that is
designed for Swift.

The Logger struct is the main interface for configuration and logging.

#### Usage

When the logger is initialized, the subsystem is inferred from the calling
context, and the category is derived from the type and the subsystem.

```swift
let log = Logger(for: DemoType.self)
```

It follows the modifier pattern in which a log instance is immutable from
the public API, and a modifier can configure and return a new log. The
most common property that can be configured this way is the level.

```swift
log.info("Test")
```

The log record may contain information to be redacted when persisted as such:

```swift
log.info("Test for id:", redacting: "abc123")
```

In Swift 5.2 and later, the `log()` method can be left off since logging is
intrinsic to what the lagger does:

```swift
log.info("Test")
```

##### Levels in order of increasing significance.

Level    | Effect
-------- | -------------------------------------------------------------
debug    | In memory logging only.
info     | Low importance. May get pruned from logs.
standard | Default logging level.
error    | Suitable for logging recoverable errors.
fault    | Suitable for logging programming errors. Provides backtraces.
