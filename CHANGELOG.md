# CHANGELOG

**NOTE:** Entries are ordered chronologically with the newest entries at the
top.

## iOS Companion 3.1.0

The following API changes have been made:
- Added a `FeatureManager` API to check whether a feature is supported by the Companion platform.
- Implemented an async variant of the `sendQuery` method in `SecuredCarChannel`.

## iOS Companion 3.0.1

### Binaries Moved

For consistency, prebuilt binaries have been moved from the `Binary`
directory to the new `Binaries` directory.

## iOS Companion 3.0.0

### Concurrency Enforcement

#### Overview

The iOS Companion SDK has always required that calls to the public API be
made from the main thread, but until now did not enforce that at compile time.
Since the iOS Companion SDK already requires Swift version 5.7+ and iOS
version 13+, it is prudent to introduce modern Swift concurrency now so we can
enforce concurrency correctness at compile time and begin taking greater
advantage of Swift concurrency.

#### Guidance

Note: You may not need to make any changes if you’ve already adopted modern
Swift concurrency in your app.

This update to iOS Companion SDK 3.0 is a potentially breaking change that
enforces at compile time that all calls to the public Companion API be made
from the MainActor. As such, any direct calls to the Companion public API must
either do so on the MainActor or from a context which awaits the call to
Companion. The reference app and other components (e.g. CalendarSync) have been
updated accordingly and will be released simultaneously with the Companion SDK.

The simplest solution is to mark your app’s entry point as a MainActor and
ensure that any callbacks to that class are also marked as such. Overall, if
you’ve already been taking care of concurrency correctness this should be a
minor change or possibly no change at all.

#### Reference App Example Changes

**TrustedDeviceModel**

`TrustedDeviceModel` is the main superclass that interacts directly with the
Companion SDK, so mark it with `MainActor`.

```swift
@MainActor
open class TrustedDeviceModel:
  NSObject,
  ConnectionManagerAssociationDelegate,
  TrustAgentManagerDelegate,
  ObservableObject
{
…
```

**TrustedDeviceMethodChannel**

`TrustedDeviceMethodChannel` is the `TrustedDeviceModel` subclass that binds to
Flutter. It inherits `MainActor` from `TrustedDeviceModel` so it already
inherits the `MainActor`. However, you need to make sure callbacks registered
with Flutter get processed on the MainActor so for example in this case mark
the callback as nonisolated, wrap the callback in a Task and await the calls on
Companion.

```swift
  private func setUpTrustedDeviceCallHandler() {
    trustedDeviceMethodChannel.setMethodCallHandler(handle)
  }

  nonisolated private func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
    ) {
    Task { [weak self] in
      switch call.method {

      case FLTTrustedDeviceConstants.open_SECURITY_SETTINGS:
        await self?.openSettings()
…
```
