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
@_implementationOnly import AndroidAutoCompanionProtos

/// Represents a query response that can be sent to a remote car.
public struct QueryResponse: Equatable {
  /// A unique identifier for a query.
  public let id: Int32

  /// `True` to indicate that the query was successful and that the `response` is that of a
  /// successful query.
  public let isSuccessful: Bool

  /// The actual response to a query.
  public let response: Data
}

extension QueryResponse {
  /// Converts this `QueryResponse` to its proto representation in `Data` form.
  func toProtoData() throws -> Data {
    var queryResponseProto = Com_Google_Companionprotos_QueryResponse()

    queryResponseProto.queryID = self.id
    queryResponseProto.success = self.isSuccessful
    queryResponseProto.response = self.response

    return try queryResponseProto.serializedData()
  }
}
