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

import AndroidAutoConnectedDeviceTransport
import AndroidAutoCoreBluetoothProtocols
import AndroidAutoCoreBluetoothProtocolsMocks
import Foundation

@testable import AndroidAutoConnectedDeviceManager

/// A mock of the `SecuredCarChannel`.
public class SecuredCarChannelMock: SecuredCarChannelPeripheral {
  private var receivedMessageObservations: [UUID: (SecuredCarChannel, Data) -> Void] = [:]
  private var messageRecipientToObservations: [UUID: UUID] = [:]

  public var queryID: Int32 = 0
  private var receivedQueryObservations: [UUID: (Int32, Query) -> Void] = [:]
  private var queryRecipientToObservations: [UUID: UUID] = [:]

  private var queryResponseHandlers: [Int32: ((QueryResponse) -> Void)] = [:]

  public var writtenQueries: [Query] = []
  public var writtenQueryResponses: [QueryResponse] = []
  public var writtenMessages: [Data] = []

  public var car: Car
  public var isValid = true
  public var blePeripheral: BLEPeripheral

  public var peripheral: AnyTransportPeripheral {
    blePeripheral as AnyTransportPeripheral
  }

  public var id: String {
    return car.id
  }

  public var name: String? {
    return car.name
  }

  public convenience init(id: String, name: String?) {
    self.init(car: Car(id: id, name: name))
  }

  public init(car: Car) {
    self.car = car
    blePeripheral = PeripheralMock(name: car.name)
  }

  public func reset() {
    receivedMessageObservations.removeAll()
    messageRecipientToObservations.removeAll()
    writtenMessages = []
  }

  /// Simulates a message being received from a recipient on the remote car.
  public func triggerMessageReceived(_ message: Data, from recipient: UUID) {
    if let id = messageRecipientToObservations[recipient] {
      receivedMessageObservations[id]?(self, message)
    }
  }

  public func triggerQuery(_ query: Query, queryID: Int32, from recipient: UUID) {
    if let id = queryRecipientToObservations[recipient] {
      receivedQueryObservations[id]?(queryID, query)
    }
  }

  public func triggerQueryResponse(_ queryResponse: QueryResponse) {
    if let handler = queryResponseHandlers[queryResponse.id] {
      handler(queryResponse)
    }
  }

  private func makeMockError() -> Error {
    return NSError(domain: "", code: 0, userInfo: nil)
  }
}

extension SecuredCarChannelMock: SecuredCarChannel {
  public func writeEncryptedMessage(
    _ message: Data,
    to recipient: UUID,
    completion: ((Bool) -> Void)?
  ) throws {
    if !isValid {
      completion?(false)
      throw makeMockError()
    }

    writtenMessages.append(message)
    completion?(true)
  }

  public func sendQuery(
    _ query: Query,
    to recipient: UUID,
    response: @escaping ((QueryResponse) -> Void)
  ) throws {
    if !isValid {
      throw makeMockError()
    }

    writtenQueries.append(query)

    queryResponseHandlers[queryID] = response
    queryID += 1
  }

  public func sendQueryResponse(_ queryResponse: QueryResponse, to recipient: UUID) throws {
    if !isValid {
      throw makeMockError()
    }

    writtenQueryResponses.append(queryResponse)
  }

  public func observeMessageReceived(
    from recipient: UUID,
    using observation: @escaping (SecuredCarChannel, Data) -> Void
  ) -> ObservationHandle {
    let id = UUID()
    receivedMessageObservations[id] = observation

    // This should always resolve due to the `if` check above.
    messageRecipientToObservations[recipient] = id

    return ObservationHandle { [weak self] in
      self?.receivedMessageObservations.removeValue(forKey: id)
      self?.messageRecipientToObservations[recipient] = nil
    }
  }

  public func observeQueryReceived(
    from recipient: UUID,
    using observation: @escaping ((Int32, Query) -> Void)
  ) throws -> ObservationHandle {
    let id = UUID()
    receivedQueryObservations[id] = observation

    // This should always resolve due to the `if` check above.
    queryRecipientToObservations[recipient] = id

    return ObservationHandle { [weak self] in
      self?.receivedQueryObservations.removeValue(forKey: id)
      self?.queryRecipientToObservations[recipient] = nil
    }
  }
}
