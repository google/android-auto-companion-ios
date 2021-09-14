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

/// A handle for responding to a query.
public class QueryResponseHandle {
  /// A closure that should take a `Data` object that acts as a response and a boolean indicating
  /// if the response is successful.
  private let responder: (Data, Bool) throws -> Void

  init(responder: @escaping (Data, Bool) throws -> Void) {
    self.responder = responder
  }

  /// Responds to a query with the given `response` and a Boolean to indicate if the query was
  /// successful.
  ///
  /// The format of the `response` and definition of a successful query is feature-defined.
  ///
  /// - Parameters:
  ///   - response: The actual response data to send to a remote car.
  ///   - isSuccessful: `true` to indicate to the car if the query was successful.
  public func respond(with response: Data, isSuccessful: Bool) throws {
    try responder(response, isSuccessful)
  }
}
