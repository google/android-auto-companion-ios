// Copyright 2023 Google LLC
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

private import AndroidAutoLogger
public import Foundation
internal import AndroidAutoCompanionProtos

typealias PeriodicPingMessage = Com_Google_Companionprotos_PeriodicPingMessage

public class PeriodicPingManager: FeatureManager {
  static let recipientUUID = UUID(uuidString: "9eb6528d-bb65-4239-b196-6789196cf2a9")!
  private static let log = Logger(for: PeriodicPingManager.self)

  public override var featureID: UUID { Self.recipientUUID }
  var connectedCar: Car?

  // MARK: - Overriding Methods

  public override func onMessageReceived(_ message: Data, from car: Car) {
    guard let periodicPingMessage = try? PeriodicPingMessage(serializedBytes: message) else {
      Self.log.error("Failed to decode message from serialized data.")
      return
    }
    handlePeriodicPingMessage(periodicPingMessage, from: car)
  }

  public override func onSecureChannelEstablished(for car: Car) {
    Self.log("onSecureChannelEstablished: \(car).")
    connectedCar = car
  }

  public override func onCarDisconnected(_ car: Car) {
    Self.log("onCarDisconnected: \(car).")
    guard connectedCar == car else {
      Self.log("\(String(describing: connectedCar)) is still connected. Ignore.")
      return
    }
    connectedCar = nil
  }

  // MARK: - Private Methods

  private func handlePeriodicPingMessage(_ message: PeriodicPingMessage, from car: Car) {
    switch message.messageType {
    case .ping:
      handlePingMessage(from: car)
    default:
      Self.log.error("Received message of type: \(message.messageType). Ignore.")
    }
  }

  private func handlePingMessage(from car: Car) {
    do {
      try sendAckMessage(to: car)
    } catch {
      Self.log.error("Failed to send Ack message to car: \(String(describing: car.name))).")
    }
  }

  private func sendAckMessage(to car: Car) throws {
    let message = try createAckMessage()
    try sendMessage(message, to: car)
  }

  private func createAckMessage() throws -> Data {
    var message = PeriodicPingMessage()
    message.messageType = .ack
    let data = try message.serializedData()
    return data
  }
}
