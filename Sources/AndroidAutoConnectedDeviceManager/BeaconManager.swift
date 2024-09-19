// Copyright 2024 Google LLC
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

#if os(iOS)

  private import AndroidAutoLogger
  import CoreLocation
  internal import Foundation

  // Set `featureUUID` at file level because `BeaconManagerImpl` uses generic type and thus does not
  // allow static stored properties.
  enum BeaconManagerConstants {
    static let featureUUID = UUID(uuidString: "9eb6528d-bb65-4239-b196-6789196cf2b1")!
  }

  /// Abstracts beacon managers from available implementations.
  public protocol BeaconManager {}

  protocol BeaconMonitor: Sendable {
    associatedtype Condition: Sendable
    associatedtype Events

    init(_ name: String) async

    var events: Events { get async }

    func add(_ condition: Condition, identifier: String) async

    func startMonitoringBeacon(uuid: UUID) async
  }

  @available(iOS 17, *)
  extension CLMonitor: BeaconMonitor {
    private static let log = Logger(for: CLMonitor.self)

    func startMonitoringBeacon(uuid: UUID) async {
      let beacon = CLMonitor.BeaconIdentityCondition(uuid: uuid, major: 1, minor: 1)

      Self.log("Start monitoring \(beacon).")
      add(beacon, identifier: "AAECompanionBeacon")

      Self.log("Start monitoring beacon events.")
      Task {
        do {
          for try await event in self.events {
            Self.log("Observed beacon status change; status changed to \(event.state).")
          }
        } catch {
          Self.log.error("Failed to monitor beacon events, error: \(error).")
        }
      }
    }
  }

  /// Monitor the car's iBeacon for reconnection.
  ///
  /// When discovering the iBeacon, iOS will automatically relaunch this app if necessary so it can
  /// reconnect to the car.
  @available(iOS 17, *)
  @MainActor class BeaconManagerImpl<Monitor: BeaconMonitor>: FeatureManager, BeaconManager {
    private static var log: Logger { Logger(for: BeaconManagerImpl.self) }

    public override var featureID: UUID {
      return BeaconManagerConstants.featureUUID
    }

    private let uuidConfig: UUIDConfig
    let beaconMonitor: Monitor?

    init(
      connectedCarManager: ConnectedCarManager,
      uuidConfig: UUIDConfig,
      monitorType: Monitor.Type = CLMonitor.self
    ) async {
      self.uuidConfig = uuidConfig
      beaconMonitor = await monitorType.init("AAECompanionBeaconMonitor")

      super.init(connectedCarManager: connectedCarManager)

      await enableBeacon()
    }

    func enableBeacon() async {
      requestLocationPermissionIfNeeded()

      guard let monitor = beaconMonitor else {
        Self.log.error("Beacon monitor is not initialized.")
        return
      }

      guard let beaconUUID = self.uuidConfig.beaconUUID else {
        Self.log.error("Beacon UUID is not configured.")
        return
      }

      await monitor.startMonitoringBeacon(uuid: beaconUUID)
    }

    private func requestLocationPermissionIfNeeded() {
      let locationManager = CLLocationManager()

      switch locationManager.authorizationStatus {
      case .notDetermined, .authorizedWhenInUse:
        Self.log("Requesting location permission.")
        locationManager.requestAlwaysAuthorization()
      default:
        Self.log(
          "Current location permission is \(locationManager.authorizationStatus); don't ask for permission."
        )
      }
    }
  }

  /// Creates `BeaconManager` instances if supported.
  ///
  /// For iOS 17 and above, the factory makes an instance to monitor the iBeacon specified in
  /// the plist. When a status change of the beacon is detected, an event is delivered and will
  /// launch the app if it is not already running.
  /// There should only be ONE instance when the app is running.
  @MainActor public class BeaconManagerFactory {
    private static let log = Logger(for: BeaconManagerFactory.self)

    public init() {}

    /// Make a new `BeaconManager` if supported, otherwise return `nil`.
    ///
    /// Parameters:
    /// - connectedCarManager: The connected car manager which will deliver connection events to the
    ///   beacon manager.
    /// - uuidConfig: The uuid configurations for the app. Its beaconUUID will be monitored by the
    ///   beacon monitor.
    public func makeBeaconManager(
      connectedCarManager: ConnectedCarManager,
      uuidConfig: UUIDConfig
    ) async -> (any BeaconManager)? {
      guard #available(iOS 17, *) else {
        Self.log("BeaconManager is not supported on this iOS version.")
        return nil
      }

      return await BeaconManagerImpl(
        connectedCarManager: connectedCarManager, uuidConfig: uuidConfig)
    }
  }

#endif
