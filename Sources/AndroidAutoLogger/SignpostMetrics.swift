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

import Foundation
import os.log

#if canImport(MetricKit)
  import MetricKit
#endif

/// Signpost metric handler providing the internal implementation for a signpost.
///
/// This protocol is only intended for private use, but is marked internal here to accommodate
/// unit testing.
@available(macOS 12.0, *)
protocol SignpostMetricsHandler {
  /// Indicates whether this handler is valid for posting metrics.
  var isValid: Bool { get }

  /// Create a handler with the specified category.
  ///
  /// - Parameter category: Name of the category for the custom metric.
  init(category: String)

  /// Post the signpost marker for metrics aggregation if supported.
  ///
  /// For the system handler if available on the current system, post the signpost metric using
  /// `MetricKit` for on-device aggregation.
  ///
  /// See https://developer.apple.com/documentation/metrickit/3214364-mxsignpost
  ///
  /// If it's an unsupported handler, errors will be logged.
  ///
  /// - Parameters:
  ///   - marker: Signpost marker to post.
  ///   - dso: Do not specify as the value is automatically assigned internally.
  func post(_ marker: SignpostMarker, dso: UnsafeRawPointer)
}

/// Wrapper for the signpost metrics that checks for `MetricKit` support on the current system and
/// provides a fallback that logs error messages if not.
///
/// An instance represents a single category and role used for posting named signposts.
@available(macOS 12.0, *)
public struct SignpostMetrics {
  /// Indicates whether signpost metric logging is available on the current system.
  public static let isSystemSupported: Bool = {
    #if canImport(MetricKit)
      return true
    #else
      return false
    #endif
  }()

  /// Handler providing the internal implementation.
  private let handler: SignpostMetricsHandler

  /// Creates a new signpost metric with the specified category.
  ///
  /// - Parameter category: Category for the new signpost metrics.
  public init(category: String) {
    #if canImport(MetricKit) && os(iOS)
      handler = SystemSignpostMetrics(category: category)
    #else
      handler = UnavailableSignpostMetrics(category: category)
    #endif
  }

  init(handler: SignpostMetricsHandler) {
    self.handler = handler
  }

  /// Post the signpost metric using `MetricKit` if it's available on the current system.
  ///
  /// Errors will be logged if the system doesn't support `MetricKit`.
  ///
  /// See https://developer.apple.com/documentation/metrickit/3214364-mxsignpost
  ///
  /// - Parameters:
  ///   - marker: Marker to post.
  ///   - dso: Do not specify as the value is automatically assigned internally.
  public func post(_ marker: SignpostMarker, dso: UnsafeRawPointer = #dsohandle) {
    handler.post(marker, dso: dso)
  }

  /// Post the signpost metric if the system supports it, otherwise it's a no-op.
  ///
  /// See https://developer.apple.com/documentation/metrickit/3214364-mxsignpost
  /// - Parameters:
  ///   - marker: Marker to post.
  ///   - dso: Do not specify as the value is automatically assigned internally.
  public func postIfAvailable(_ marker: SignpostMarker, dso: UnsafeRawPointer = #dsohandle) {
    if handler.isValid {
      post(marker, dso: dso)
    }
  }
}

#if canImport(MetricKit)
  /// Signpost Metrics handler implemented using `MetricKit`.
  #if os(iOS)
    private struct SystemSignpostMetrics: SignpostMetricsHandler {
      private let logHandle: OSLog

      var isValid: Bool { true }

      fileprivate init(category: String) {
        logHandle = MXMetricManager.makeLogHandle(category: category)
      }

      fileprivate func post(_ marker: SignpostMarker, dso: UnsafeRawPointer = #dsohandle) {
        mxSignpost(marker.role.systemType, dso: dso, log: logHandle, name: marker.name)
      }
    }
  #endif

  // MARK: - Role Conversions

  extension SignpostMarker.Role {
    /// Convert the role to the corresponding `OSSignpostType`.
    fileprivate var systemType: OSSignpostType {
      switch self {
      case .event: return .event
      case .begin: return .begin
      case .end: return .end
      }
    }
  }
#endif

/// Signpost Metrics handler implemented to support systems without `MetricKit`.
///
/// Calling methods on this implementation do not log any metrics. Rather they provide a safe
/// implementation that simply logs errors for such attempts.
@available(macOS 12.0, *)
private struct UnavailableSignpostMetrics: SignpostMetricsHandler {
  static let log = Logger(for: UnavailableSignpostMetrics.self)

  /// Just a placeholder since no valid handler is available.
  var isValid: Bool { false }

  fileprivate init(category: String) {
    Self.log.error(
      "Instantiating signpost metric for category: [\(category)] on unsupported platform.")
  }

  fileprivate func post(_ marker: SignpostMarker, dso: UnsafeRawPointer = #dsohandle) {
    Self.log.error("Attempt to post signpost metric: [\(marker.name)] on unsupported platform.")
  }
}
