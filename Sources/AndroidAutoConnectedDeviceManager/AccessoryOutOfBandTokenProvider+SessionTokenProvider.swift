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

  // MARK: - SessionTokenProvider

  extension AccessoryOutOfBandTokenProvider {
    /// Token provider for a given EASession.
    class SessionTokenProvider: NSObject {
      private static let log = Logger(for: SessionTokenProvider.self)
      private let session: EASession
      private var reader: StreamReader!
      private var token: OutOfBandToken?

      var accessory: EAAccessory? { session.accessory }
      var isConnected: Bool { accessory?.isConnected ?? false }

      /// Create a new accessory session.
      ///
      /// Note that we can only have one session for a given accessory+protocol pair.
      init?(accessory: EAAccessory, forProtocol protocolString: String) {
        guard let session = EASession(accessory: accessory, forProtocol: protocolString) else {
          return nil
        }
        guard let inputStream = session.inputStream else {
          return nil
        }

        self.session = session

        super.init()

        self.reader = StreamReader(stream: inputStream) { [weak self] token in
          Self.log("Stream reader parsed token.")
          self?.token = token
        }
        accessory.delegate = self

        Self.log("New session for: \(accessory) with protocol: \(protocolString).")
      }

      deinit {
        invalidate()
      }

      /// Invalidate the session resources to allow the session to be reclaimed.
      ///
      /// The system only allows one `EASession` per accessory+protocol pair, so we need to make
      /// sure we cleanup the session once we are done using it so the system can free it. If we
      /// fail to cleanup the session properly, the system will no release the underlying session
      /// and subsequent attempts to create a new session will fail.
      ///
      /// This session will no longer be usable once invalidated.
      func invalidate() {
        Self.log.info("Invalidating session.")
        accessory?.delegate = nil
        reader.invalidate()
        // Close the output stream for proper cleanup even though we never directly open it.
        session.outputStream?.close()
        token = nil
      }
    }
  }

  // MARK: - OutOfBandTokenProvider Conformance

  extension AccessoryOutOfBandTokenProvider.SessionTokenProvider: OutOfBandTokenProvider {
    func reset() {
      token = nil
    }

    func requestToken(completion: @escaping (OutOfBandToken?) -> Void) {
      Self.log("Requested token available: \(token != nil)")
      completion(token)
    }
  }

  // MARK: - EAAccessoryDelegate Conformance

  extension AccessoryOutOfBandTokenProvider.SessionTokenProvider: EAAccessoryDelegate {
    func accessoryDidDisconnect(_ accessory: EAAccessory) {
      Self.log("Accessory \(accessory) did disconnect.")
      reader.reset()
      reset()
    }
  }

#endif  // ExternalAccessory
