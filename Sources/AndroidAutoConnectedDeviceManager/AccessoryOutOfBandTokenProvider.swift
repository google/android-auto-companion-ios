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

#if canImport(ExternalAccessory)

  import AndroidAutoLogger
  import Foundation
  @_implementationOnly import AndroidAutoCompanionProtos

  import ExternalAccessory

  private typealias OutOfBandAssociationToken = Com_Google_Companionprotos_OutOfBandAssociationToken

  /// Controller for external MFi accessory discovery and session establishment.
  @available(iOS 13.0, *)
  final class AccessoryOutOfBandTokenProvider {
    private static let logger = Logger(for: AccessoryOutOfBandTokenProvider.self)

    private let accessoryProtocol: AccessoryProtocol

    private var source: CoalescingOutOfBandTokenProvider<SessionTokenProvider>

    init?() {
      guard let accessoryProtocol = AccessoryProtocol() else {
        Self.logger.error("No matching accessory protocol found for out of band association.")
        return nil
      }

      self.accessoryProtocol = accessoryProtocol
      source = CoalescingOutOfBandTokenProvider()
    }
  }

  // MARK: - OutOfBandTokenProvider Conformance

  @available(iOS 13.0, *)
  extension AccessoryOutOfBandTokenProvider: OutOfBandTokenProvider {
    func prepareForRequests() {
      // Retain sessions for currently connected accessories.
      let connectedProviders = source.providers.filter { $0.isConnected }
      source = CoalescingOutOfBandTokenProvider(connectedProviders)

      // Fetch the current session accessory ids since each accessory can only have one session.
      let sessionIDs: Set<Int> = connectedProviders.reduce(into: []) { partialResult, provider in
        guard let id = provider.accessory?.connectionID else { return }
        partialResult.insert(id)
      }

      // Create sessions for newly connected accessories.
      EAAccessoryManager.shared().connectedAccessories.lazy.filter {
        !sessionIDs.contains($0.connectionID) && self.accessoryProtocol.isSupported(by: $0)
      }.compactMap {
        SessionTokenProvider(accessory: $0, forProtocol: self.accessoryProtocol.identifier)
      }.forEach {
        source.register($0)
      }
      Self.logger(
        "Preparing accessory out of band token provider with \(source.providers.count) sessions.")
    }

    /// Tear down accessory sessions if any since they are only needed for association.
    func closeForRequests() {
      source = CoalescingOutOfBandTokenProvider()
    }

    func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
      source.requestToken(completion: completion)
    }

    func reset() {
      source.reset()
    }
  }

  // MARK: - AccessoryProtocol

  @available(iOS 13.0, *)
  extension AccessoryOutOfBandTokenProvider {
    /// Supported accessory protocol for Out of Band Association.
    struct AccessoryProtocol {
      private static let logger = Logger(for: AccessoryProtocol.self)
      private static let accessoryProtocolsKey = "UISupportedExternalAccessoryProtocols"
      private static let protocolSuffix = "oob-association"

      /// Protocol string for out of band association.
      let identifier: String

      /// Initialize with the registered accessory protocol string if any, otherwise return `nil`.
      ///
      /// Searches the app's main bundle for registered external accessory protocols with a suffix
      /// matching `oob-association`. The first such protocol string found will be used.
      init?() {
        guard
          let accessoryProtocols = Bundle.main.infoDictionary?[Self.accessoryProtocolsKey]
            as? [String]
        else {
          Self.logger.error("The Info dictionary does not define External Accessory protocols.")
          return nil
        }

        guard
          let identifier = accessoryProtocols.first(where: { $0.hasSuffix(Self.protocolSuffix) })
        else {
          Self.logger.error("No External Accessory protocol with suffix: \(Self.protocolSuffix)")
          return nil
        }

        Self.logger.info("Found supported accessory protocol: \(identifier)")
        self.init(identifier)
      }

      /// Create the accessory protocol matcher directly from the protocol string.
      ///
      /// - Parameter identifier: The protocol string to  match.
      private init(_ identifier: String) {
        self.identifier = identifier
      }

      /// Determine whether this protocol is supported by the specified accessory.
      func isSupported(by accessory: EAAccessory) -> Bool {
        accessory.protocolStrings.contains(identifier)
      }
    }
  }

#endif  // ExternalAccessory