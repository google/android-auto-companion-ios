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

public import Foundation
private import AndroidAutoCompanionProtos

/// Represents a query request that can be sent to a remote car.
public struct Query: Equatable {
  /// A `Data` object that represents the query.
  public let request: Data

  /// An optional `Data` object that represents parameters that modify the query.
  public let parameters: Data?
}

extension Query {
  /// Converts this `Query` to its proto representation in `Data` form.
  func toProtoData(queryID: Int32, sender: UUID) throws -> Data {
    var queryProto = Com_Google_Companionprotos_Query()

    queryProto.id = queryID
    queryProto.sender = sender.toData()
    queryProto.request = self.request

    if let parameters = self.parameters {
      queryProto.parameters = parameters
    }

    return try queryProto.serializedData()
  }
}
