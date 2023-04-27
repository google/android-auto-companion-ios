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

import AndroidAutoLogger
import UIKit
@_implementationOnly import AndroidAutoCompanionProtos

private typealias FeatureSupportStatus = Com_Google_Companionprotos_FeatureSupportStatus
private typealias SystemQuery = Com_Google_Companionprotos_SystemQuery
private typealias SystemQueryType = Com_Google_Companionprotos_SystemQueryType
private typealias SystemUserRoleResponse = Com_Google_Companionprotos_SystemUserRoleResponse
typealias SystemUserRole = Com_Google_Companionprotos_SystemUserRole
typealias FeatureSupportResponse = Com_Google_Companionprotos_FeatureSupportResponse

/// Provides the containing application name.
protocol AppNameProvider {
  /// A localized application name or `nil` if it cannot be retrieved.
  var appName: String? { get }
}

/// A feature manager that is responsible to responding to device level queries.
class SystemFeatureManager: FeatureManager {
  private static let log = Logger(for: SystemFeatureManager.self)

  static let recipientUUID = UUID(uuidString: "892ac5d9-e9a5-48dc-874a-c01e3cb00d5d")!

  public override var featureID: UUID {
    return Self.recipientUUID
  }

  private let nameProvider: AnyDevice
  private let appNameProvider: AppNameProvider

  override public convenience init(connectedCarManager: ConnectedCarManager) {
    self.init(
      connectedCarManager: connectedCarManager,
      nameProvider: System.currentDevice,
      appNameProvider: Bundle.main
    )
  }

  init(
    connectedCarManager: ConnectedCarManager,
    nameProvider: AnyDevice,
    appNameProvider: AppNameProvider
  ) {
    self.nameProvider = nameProvider
    self.appNameProvider = appNameProvider
    super.init(connectedCarManager: connectedCarManager)
  }

  override func onQueryReceived(
    _ query: Query,
    from car: Car,
    responseHandle: QueryResponseHandle
  ) {
    guard let systemQuery = try? SystemQuery(serializedData: query.request) else {
      Self.log.error("Received query from car \(car) but unable to parse. Ignoring.")
      return
    }

    Self.log.debug("Received query from car \(car).")

    do {
      try respondToQueryMessage(systemQuery, from: car, responseHandle: responseHandle)
    } catch {
      Self.log.error("Could not send response to car: \(error.localizedDescription)")
    }
  }

  private func respondToQueryMessage(
    _ systemQuery: SystemQuery,
    from car: Car,
    responseHandle: QueryResponseHandle
  ) throws {
    switch systemQuery.type {
    case SystemQueryType.deviceName:
      let deviceName = nameProvider.name
      Self.log("Received device name query. Responding with \(deviceName)")
      try responseHandle.respond(with: Data(deviceName.utf8), isSuccessful: true)

    case SystemQueryType.appName:
      if let appName = appNameProvider.appName {
        Self.log("Received app name query. Responding with \(appName)")
        try responseHandle.respond(with: Data(appName.utf8), isSuccessful: true)
      } else {
        Self.log.error(
          """
          Received app name query but unable to retrieve name. \
          Sending unsuccessful query response.
          """
        )
        try responseHandle.respond(with: Data(), isSuccessful: false)
      }

    case SystemQueryType.isFeatureSupported:
      Self.log("Received query for feature support status.")

      let provider = featureSupportStatusProvider(for: car)
      Self.log("Feature support status provider is \(String(describing: provider))")

      let statuses: [FeatureSupportStatus] = systemQuery.payloads.compactMap { payload in
        guard let queriedFeatureID = UUID(uuidString: String(decoding: payload, as: UTF8.self))
        else {
          Self.log.error("Could not parse query \(payload) as feature ID. Ignored.")
          return nil
        }

        guard let provider else {
          return FeatureSupportStatus.with {
            $0.featureID = queriedFeatureID.uuidString
            $0.isSupported = false
          }
        }

        let isSupported = provider.isFeatureSupported(queriedFeatureID)
        let status = FeatureSupportStatus.with {
          $0.featureID = queriedFeatureID.uuidString
          $0.isSupported = isSupported
        }

        Self.log("Queried feature status: \(featureID) - \(isSupported).")
        return status
      }
      Self.log("Queried feature support statuses are \(statuses).")

      let response = FeatureSupportResponse.with {
        $0.statuses = statuses
      }
      Self.log("Sending response for support status query: \(response)")
      try responseHandle.respond(with: response.serializedData(), isSuccessful: true)

    default:
      Self.log.error(
        """
        Received query from \(car) of unknown type \(systemQuery.type). \
        Sending unsuccessful query response.
        """
      )
      try responseHandle.respond(with: Data(), isSuccessful: false)
    }
  }
}

// MARK: - User Role
extension SystemFeatureManager: ChannelFeatureProvider {
  /// Request the user role (driver/passenger) for the specified channel.
  func requestUserRole(
    with channel: SecuredCarChannel,
    completion: @escaping (UserRole?) -> Void
  ) {
    do {
      var systemQuery = SystemQuery()
      systemQuery.type = .userRole
      let systemQueryData = try systemQuery.serializedData()
      let query = Query(request: systemQueryData, parameters: nil)
      Self.log("Sending system query for user role.")
      try channel.sendQuery(query, to: Self.recipientUUID) { queryResponse in
        guard queryResponse.isSuccessful else {
          Self.log.error("Query response for user role failed.")
          completion(nil)
          return
        }
        guard
          let response = try? SystemUserRoleResponse(serializedData: queryResponse.response)
        else {
          completion(nil)
          return
        }
        completion(UserRole(response.role))
      }
    } catch {
      Self.log.error("Error sending user role query: \(error.localizedDescription)")
      completion(nil)
    }
  }
}

extension Bundle: AppNameProvider {
  /// Returns the localized name of the current application if it exists.
  var appName: String? {
    // Prefer the display name over the bundle name. The display name is usually the value that
    // appears on the user's home screen.
    //
    // Note: using object(forInfoDictionaryKey:) since this returns the localized value of a key
    // when one is available.
    return object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? object(
      forInfoDictionaryKey: "CFBundleName") as? String
  }
}

// MARK: - SystemUserRole Conversion

extension UserRole {
  init?(_ systemUserRole: SystemUserRole) {
    switch systemUserRole {
    case .driver:
      self = .driver
    case .passenger:
      self = .passenger
    case .unknown, .UNRECOGNIZED(_):
      return nil
    }
  }
}
