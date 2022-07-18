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
import Foundation
@_implementationOnly import AndroidAutoCompanionProtos

private typealias OutOfBandAssociationData = Com_Google_Companionprotos_OutOfBandAssociationData

/// Opaque type that wraps out of band association data parsed from some content.
public class OutOfBandAssociationDataSource {
  private static let log = Logger(for: OutOfBandAssociationDataSource.self)

  private let outOfBandData: OutOfBandAssociationData

  var deviceID: Data { outOfBandData.deviceIdentifier }
  var token: OutOfBandToken { outOfBandData.token }

  private init(_ outOfBandData: OutOfBandAssociationData) {
    self.outOfBandData = outOfBandData
  }
}

// MARK: - AssociationURLParser

extension OutOfBandAssociationDataSource {
  /// Extract the out of band data from a URL.
  ///
  /// The URL should be of the form:
  /// scheme://domain/associate?oobData=[base64 encoded data]
  ///
  /// - Parameter url: URL from which to extract the out of band data.
  /// - Throws: If the out of band data cannot be extracted from the URL.
  convenience public init(_ url: URL) throws {
    let outOfBandData = try AssociationURLParser.parse(url)
    self.init(outOfBandData)
  }

  /// Performs the parsing of the URL's association query.
  enum AssociationURLParser {
    private static let log = Logger(for: AssociationURLParser.self)

    private static let queryKey = "oobData"

    fileprivate static func parse(_ url: URL) throws -> OutOfBandAssociationData {
      guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        log.error("URL could components could not be extracted.")
        throw Error.invalidURL
      }

      // Extract the key/value pair assignments from the query.
      guard let assignments = components.queryItems else {
        log.error("No query items to process.")
        throw Error.missingQuery
      }

      guard let queryAssignment = assignments.first(where: { $0.name == queryKey }) else {
        Self.log.error("URL query is missing out of band data.")
        throw Error.missingOutOfBandData
      }

      guard let oobComponent = queryAssignment.value else {
        Self.log.error("No value associated with out of band query.")
        throw Error.missingOutOfBandData
      }

      let oobBase64String = try toBase64(urlSafeBase64: oobComponent)
      guard
        let oobTokenData = Data(
          base64Encoded: String(oobBase64String), options: .ignoreUnknownCharacters)
      else {
        Self.log.error("URL query out of band data could not be base64 decoded.")
        throw Error.invalidBase64Encoding
      }
      let outOfBandData = try OutOfBandAssociationData(serializedData: oobTokenData)

      Self.log("Parsed out of band data from URL for car: \(outOfBandData.deviceIdentifier.hex)")

      return outOfBandData
    }

    /// Convert from URL Safe Base64 to standard Base64.
    ///
    /// Replace URL Safe percent encoded characters with their decoded characters.
    /// Map URL safe Base64 characters to their counterparts:
    ///   "_" -> "/"
    ///   "-" -> "+"
    ///
    /// - Parameter urlSafeBase64: URL Safe Base64 encoded string.
    /// - Returns: Standard Base64 encoded string.
    /// - Throws: Error if the URL safe string has an invalid percent encoding.
    static func toBase64(urlSafeBase64: String) throws -> String {
      guard
        let base64String =
          urlSafeBase64.removingPercentEncoding?
          .replacingOccurrences(of: "_", with: "/")
          .replacingOccurrences(of: "-", with: "+")
      else {
        Self.log.error("Failed to decode URL Safe Base64 encoding.")
        throw Error.invalidBase64Encoding
      }
      return base64String
    }
  }
}

// MARK: - AssociationURLParser.Error

extension OutOfBandAssociationDataSource.AssociationURLParser {
  enum Error: Swift.Error {
    case invalidURL
    case missingQuery
    case missingOutOfBandData
    case invalidBase64Encoding
  }
}
