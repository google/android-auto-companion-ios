public import AndroidAutoConnectedDeviceManager
private import AndroidAutoLogger
public import Foundation
internal import SwiftProtobuf
internal import AndroidAutoConnectionHowitzerV2Protos

internal typealias HowitzerMessage =
  Com_Google_Android_Connecteddevice_Connectionhowitzer_Proto_HowitzerMessage

/// Input argument config for bandwidth test.
public struct HowitzerConfig {
  /// Bandwidth test payload size in bytes.
  let payloadSize: Int32
  /// Number of payloads to be sent/received.
  let payloadCount: Int32
  /// If IHU is in charge of sending payloads.
  let sentFromIHU: Bool

  public init(
    payloadSize: Int32 = 900,
    payloadCount: Int32 = 100,
    sentFromIHU: Bool = true
  ) {
    self.payloadSize = payloadSize
    self.payloadCount = payloadCount
    self.sentFromIHU = sentFromIHU
  }
}

/// Test result for bandwidth test.
public struct HowitzerResult {
  /// If the test result is valid.
  public let isValid: Bool
  /// Timestamp when each payload was received.
  public let payloadReceivedTimestamps: [TimeInterval]
  /// Timestamp when the test started.
  public let testStartTime: TimeInterval

  init(
    isValid: Bool,
    payloadReceivedTimestamps: [TimeInterval],
    testStartTime: TimeInterval
  ) {
    self.isValid = isValid
    self.payloadReceivedTimestamps = payloadReceivedTimestamps
    self.testStartTime = testStartTime
  }
}

/// A feature that sends a random message of a hard-coded length when it receives a corresponding
/// message from the head unit.
///
/// This feature is meant to test the throughput of the Connected Device Manager platform.
public class ConnectionHowitzerManagerV2: FeatureManager {
  static let recipientUUID = UUID(uuidString: "b75d6a81-635b-4560-bd8d-9cdf83f32ae7")!

  public override var featureID: UUID { Self.recipientUUID }

  private static let log = Logger(for: ConnectionHowitzerManagerV2.self)

  /// Delegate to be notified of completion of a throughput test.
  public weak var delegate: ConnectionHowitzerManagerV2Delegate?

  private var currentState: State
  private var payloadCounter: Int

  private(set) var connectedCar: Car?
  private(set) var testID: UUID?
  private(set) var config: HowitzerConfig
  private(set) var testStartTime: TimeInterval?
  private(set) var payloadReceivedTimestamps: [TimeInterval]

  private enum State {
    /// Pending test config.
    case uninitiated
    /// Sent config to IHU, waiting for ack.
    case pendingConfigAck
    /// Phone is the sender sending payloads IHU.
    case pendingResult
    /// IHU is the sender, counting received payloads.
    case countingPayload
    /// Send result to IHU, waiting for ack.
    case pendingResultAck
  }

  public override init(connectedCarManager: ConnectedCarManager) {
    self.currentState = .uninitiated
    self.config = HowitzerConfig()
    self.payloadReceivedTimestamps = []
    self.payloadCounter = 0
    super.init(connectedCarManager: connectedCarManager)
  }

  public override func onSecureChannelEstablished(for car: Car) {
    Self.log("onSecureChannelEstablished: \(car).")
    // Reset every time a car is connected to ensure we have a clean slate.
    reset()
    connectedCar = car
  }

  public override func onCarDisconnected(_ car: Car) {
    Self.log("onCarDisconnected: \(car).")
    guard connectedCar == car else {
      Self.log("\(String(describing: connectedCar)) is still connected, ignore.")
      return
    }

    reset()
    connectedCar = nil
  }

  public override func onMessageReceived(_ message: Data, from car: Car) {
    handleHowitzerMessage(message, from: car)
  }

  /// Starts a bandwidth test with user specified config.
  ///
  /// - Parameter:
  ///   - config: The configuration of the bandwidth test.
  public func start(with config: HowitzerConfig) {
    self.config = config

    guard currentState == .uninitiated else {
      Self.log.error("Exists ongoing test. Cannot start test.")
      onTestFailed()
      return
    }

    guard let car = connectedCar else {
      Self.log.error("No car connected. Cannot start test.")
      onTestFailed()
      return
    }

    Self.log("Started throughput test!")
    let newTestID = UUID()
    testID = newTestID
    let message = HowitzerMessage(testID: newTestID, config: config)
    do {
      Self.log("Sending testing config to IHU.")
      try sendMessage(message, to: car)
      currentState = .pendingConfigAck
    } catch {
      Self.log.error("Failed to send config to IHU, abort.")
      onTestFailed()
    }
  }

  private func handleHowitzerMessage(_ message: Data, from car: Car) {
    Self.log("Received message, current state is \(currentState).")
    switch currentState {
    case .pendingConfigAck:
      handleConfigAckMessage(message, from: car)
    case .pendingResult:
      handleResult(message, from: car)
    case .countingPayload:
      handlePayload(message, from: car)
    case .pendingResultAck:
      handleResultAck(message, from: car)
    default:
      Self.log.error("Received message in \(currentState), ignore.")
    }
  }

  private func handleConfigAckMessage(_ message: Data, from car: Car) {
    guard let howitzerMessage = try? HowitzerMessage(serializedBytes: message) else {
      Self.log.error("Failed to decode message from serialized data.")
      onTestFailed()
      return
    }

    guard howitzerMessage.messageType == .ack else {
      Self.log.error("Received message type is not ACK, ignore.")
      onTestFailed()
      return
    }

    if config.sentFromIHU {
      Self.log("Handle Ack Message: IHU is sender; setting state to \(currentState).")
      currentState = .countingPayload
      testStartTime = Date().timeIntervalSince1970
      return
    }

    for index in 1...config.payloadCount {
      Self.log("Sending payload #\(index)")
      do {
        try sendPayload(to: car)
      } catch {
        Self.log.error("Failed to initiate sending message #\(index).")
        onTestFailed()
        return
      }
    }

    Self.log("All payloads have been queued to be sent.")
    currentState = .pendingResult
  }

  private func sendPayload(to car: Car) throws {
    try sendMessage(generateRandomMessage(length: config.payloadSize), to: car)
  }

  private func generateRandomMessage(length: Int32) -> Data {
    return Data((0..<length).map { _ in UInt8.random(in: UInt8.min...UInt8.max) })
  }

  private func handleResult(_ message: Data, from car: Car) {
    guard let howitzerMessage = try? HowitzerMessage(serializedBytes: message) else {
      Self.log.error("Failed to decode message from serialized data.")
      onTestFailed()
      return
    }

    guard validateResultMessage(howitzerMessage) else {
      Self.log.error("Failed to validate incoming message, abort test.")
      onTestFailed()
      return
    }

    // Record test results from IHU message.
    let testStartTime = howitzerMessage.result.testStartTimestamp.timeIntervalSince1970
    self.testStartTime = testStartTime

    for interval in howitzerMessage.result.payloadReceivedTimestamps {
      payloadReceivedTimestamps.append(interval.timeIntervalSince1970)
    }

    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: payloadReceivedTimestamps,
      testStartTime: testStartTime
    )

    Self.log(
      "Test ID:\(String(describing: testID)); Test Result: \(result))."
    )

    guard let car = connectedCar else {
      Self.log.error("No car connected, abort test.")
      onTestFailed()
      return
    }

    do {
      try sendResultAck(to: car)
    } catch {
      Self.log.error("Failed to send RESULT_ACK to IHU.")
    }

    onTestCompletedSuccessfully(with: config, with: result)
  }

  private func validateResultMessage(_ message: HowitzerMessage) -> Bool {
    guard message.messageType == .result else {
      Self.log.error("Expecting result message but received \(message.messageType) message, abort.")
      return false
    }

    guard let testID,
      message.config.testID.caseInsensitiveCompare(testID.uuidString) == .orderedSame
    else {
      Self.log.error(
        "Phone testID: \(String(describing: testID)) and IHU testID: \(message.config.testID) do not match, abort."
      )
      return false
    }

    guard message.result.isValid else {
      Self.log.error("Received invalid result from IHU.")
      return false
    }

    Self.log("Incoming RESULT message validated.")
    return true
  }

  private func sendResultAck(to car: Car) throws {
    Self.log("Send result ack to IHU.")
    let message = HowitzerMessage(type: .ack)
    let data = try message.serializedData()
    try sendMessage(data, to: car)
  }

  private func handlePayload(_ message: Data, from car: Car) {
    guard message.count == config.payloadSize else {
      Self.log.error(
        "Received payload size(\(message.count)) is different from config specification(\(config.payloadSize))."
      )
      onTestFailed()
      return
    }

    payloadCounter += 1
    payloadReceivedTimestamps.append(Date().timeIntervalSince1970)
    Self.log("Handle payload #\(payloadCounter).")

    if payloadCounter == config.payloadCount {
      Self.log("All payloads have been received.")

      guard let message = createResultMessage() else {
        Self.log.error("Failed to create result message, abort.")
        onTestFailed()
        return
      }

      do {
        Self.log("Send result to IHU.")
        try sendMessage(message, to: car)
        currentState = .pendingResultAck
      } catch {
        Self.log.error("Failed to send result to IHU, abort.")
        onTestFailed()
      }
    }
  }

  private func createResultMessage() -> HowitzerMessage? {
    guard let testStartTime, let testID else {
      Self.log.error(
        "Cannot fetch all the data. TestID: \(String(describing: testID)); testStartTime: \(String(describing: testStartTime)), abort test."
      )
      return nil
    }

    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: payloadReceivedTimestamps,
      testStartTime: testStartTime
    )
    return HowitzerMessage(testID: testID, config: config, result: result)
  }

  private func sendMessage(_ message: HowitzerMessage, to car: Car) throws {
    let data = try message.serializedData()
    try sendMessage(data, to: car)
  }

  private func handleResultAck(_ message: Data, from car: Car) {
    guard let howitzerMessage = try? HowitzerMessage(serializedBytes: message) else {
      Self.log.error("Failed to decode message from serialized data.")
      onTestFailed()
      return
    }

    guard howitzerMessage.messageType == .ack else {
      Self.log.error("Received message type is not ACK, ignore.")
      onTestFailed()
      return
    }

    guard let testStartTime else {
      Self.log.error("Failed to fetch test start time, abort.")
      onTestFailed()
      return
    }

    let result = HowitzerResult(
      isValid: true,
      payloadReceivedTimestamps: payloadReceivedTimestamps,
      testStartTime: testStartTime
    )
    onTestCompletedSuccessfully(with: config, with: result)
  }

  private func onTestCompletedSuccessfully(
    with config: HowitzerConfig,
    with result: HowitzerResult
  ) {
    Self.log("Test completed successfully. Notify delegate.")
    delegate?.connectionHowitzerManagerV2(self, testConfig: config, testCompletedResult: result)
    reset()
  }

  private func onTestFailed() {
    Self.log("Test failed. Notify delegate.")
    let result = HowitzerResult(
      isValid: false,
      payloadReceivedTimestamps: [],
      testStartTime: TimeInterval()
    )
    delegate?.connectionHowitzerManagerV2(self, testConfig: config, testCompletedResult: result)
    reset()
  }

  private func reset() {
    currentState = .uninitiated
    config = HowitzerConfig()
    testStartTime = nil
    payloadReceivedTimestamps = []
    payloadCounter = 0
    testID = nil
  }
}

/// A delegate to be notified when the test has been completed.
@MainActor public protocol ConnectionHowitzerManagerV2Delegate: AnyObject {
  /// Invoked when the howitzer test is finished.
  ///
  /// - Parameters:
  ///   - connectionHowitzerManager: The howitzer that is managing messages
  ///   - config: The config of a bandwidth test.
  ///   - result: The result of the completed bandwidth test.
  func connectionHowitzerManagerV2(
    _ connectionHowitzerManagerV2: ConnectionHowitzerManagerV2,
    testConfig config: HowitzerConfig,
    testCompletedResult result: HowitzerResult)
}
