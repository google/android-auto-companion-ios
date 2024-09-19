// Copyright 2022 Google LLC
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

public import Foundation

/// Wraps a `NotificationCenter` opaque observer for concurrency compatibility and dispatches notifications.
///
/// Allows `NotificationCenter` observers to be used in a context with strict swift concurrency.  The handler will be executed on
/// the `MainActor` and instances of the dispatcher are isolated to the `MainActor` and are hence `Sendable`.
///
/// The owner of an instance is responsible for calling `invalidate` once it is done with it. Failure to do so will cause a memory leak.
@MainActor public final class NotificationDispatcher {
  private let observer: NSObjectProtocol

  /// Create a dispatcher for the given notification.
  ///
  /// - Parameters:
  ///   - name: Name of the notification to observe.
  ///   - handler: Handler to execute when the notification is triggered.
  public init(name: Notification.Name, handler: @escaping @Sendable @MainActor () -> Void) {
    observer = NotificationCenter.default.addObserver(
      forName: name,
      object: nil,
      queue: OperationQueue.main
    ) { notification in
      // The notification observer was scheduled on the main queue, so we can assert this callback
      // to be on `MainActor`.
      MainActor.assumeIsolated(handler)
    }
  }

  /// Invalidate the dispatcher which removes its observer from the notification center.
  public func invalidate() {
    NotificationCenter.default.removeObserver(observer)
  }
}
