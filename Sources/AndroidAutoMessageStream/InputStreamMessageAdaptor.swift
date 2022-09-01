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

import AndroidAutoLogger
import Foundation
import SwiftProtobuf

/// Reads protobuf messages of a specific type from an input stream and decodes them progressively.
public struct InputStreamMessageAdaptor<Element: Message> {
  private static var log: Logger { Logger(for: InputStreamMessageAdaptor<Element>.self) }

  private let streamHandler: StreamHandler<Element>

  var isValid: Bool { streamHandler.isValid }

  /// Default size (byte count) of the buffer for reading from the stream.
  public static var defaultBufferSize: Int { StreamHandler<Element>.defaultBufferSize }

  /// Default maximum serialized size (byte count) of an element to read.
  public static var defaultMaxElementSize: Int { StreamHandler<Element>.defaultMaxElementSize }

  /// Creates an adaptor that can progressively read protobuf messages from the input stream.
  ///
  /// - Parameters:
  ///   - inputStream: Input stream from which to read the elements.
  ///   - bufferSize: Size (byte count) of the buffer for reading from the stream.
  ///   - maxElementSize: Maximum serialized size (byte count) of an element to read.
  public init(
    inputStream: InputStream,
    bufferSize: Int = Self.defaultBufferSize,
    maxElementSize: Int = Self.defaultMaxElementSize
  ) {
    precondition(bufferSize > 0, "bufferSize \(bufferSize) must be positive.")
    precondition(maxElementSize > 0, "maxElementSize \(maxElementSize) must be positive.")

    streamHandler = StreamHandler<Element>(
      inputStream: inputStream,
      bufferSize: bufferSize,
      maxElementSize: maxElementSize
    )
  }
}

extension InputStreamMessageAdaptor: SerialDecodingAdaptor {
  public func startDecoding(onElementDecoded: @escaping (Result<Element?, Error>) -> Void) {
    Self.log("Start decoding elements from stream.")
    streamHandler.startDecoding(onElementDecoded: onElementDecoded)
  }

  /// Stop decoding elements from the data source.
  public func stopDecoding() {
    Self.log("Stop decoding elements from stream.")
    streamHandler.stopDecoding()
  }
}

private class StreamHandler<Element: Message>: NSObject, StreamDelegate {
  private static var log: Logger { Logger(for: StreamHandler<Element>.self) }

  /// RunLoop period in seconds.
  private static var runLoopPeriodSeconds: Double { 0.001 }

  /// The input stream to process.
  private let inputStream: InputStream

  /// Serial queue on which the input stream's runloop is accessed for thread safety.
  private let queue = DispatchQueue(label: "InputStreamReader")

  /// Get the Runloop on which the input stream is processed.
  private var queue_runLoop: RunLoop {
    queue.sync {
      RunLoop.current
    }
  }

  /// Indicates whether the runloop should keep running.
  private var keepRunning: Bool { isValid }

  private(set) var isValid = true

  private var onElementDecoded: ((Result<Element?, Error>) -> Void)?

  private var buffer: Buffer = .empty

  static var defaultBufferSize: Int { Buffer.defaultBufferSize }

  static var defaultMaxElementSize: Int { Buffer.defaultMaxElementSize }

  private let bufferSize: Int
  private let maxElementSize: Int

  init(
    inputStream: InputStream,
    bufferSize: Int = Buffer.defaultBufferSize,
    maxElementSize: Int = Buffer.defaultMaxElementSize
  ) {
    self.inputStream = inputStream
    self.bufferSize = bufferSize
    self.maxElementSize = maxElementSize

    super.init()

    inputStream.delegate = self
  }

  public func startDecoding(onElementDecoded: @escaping (Result<Element?, Error>) -> Void) {
    self.onElementDecoded = onElementDecoded
    scheduleInputStream()
    inputStream.open()
  }

  /// Stop decoding elements from the data source.
  public func stopDecoding() {
    guard isValid else { return }

    isValid = false
    onElementDecoded = nil
    inputStream.close()
    CFRunLoopStop(queue_runLoop.getCFRunLoop())
  }

  private func scheduleInputStream() {
    // Begin a runloop on queue to process the input stream.
    queue.async { [weak self] in
      let runLoop = RunLoop.current
      self?.inputStream.schedule(in: runLoop, forMode: .common)
      Self.log("Input stream scheduled in run loop.")
      while true {
        guard self?.keepRunning ?? false else { return }
        guard
          runLoop.run(
            mode: .default,
            before: Date(timeIntervalSinceNow: Self.runLoopPeriodSeconds)
          )
        else {
          Self.log.error("Failed to run the input stream runloop.")
          self?.onElementDecoded?(
            .failure(InputStreamMessageAdaptor<Element>.StreamError.runloopFailedToRun))
          return
        }
      }
    }
  }

  private func readData() {
    dispatchPrecondition(condition: .onQueue(queue))

    guard let onElementDecoded = onElementDecoded else { return }

    do {
      // Intercept buffer decoding to verify the recipient still wants to receive events.
      try buffer.read(
        from: inputStream,
        bufferSize: bufferSize,
        maxElementSize: maxElementSize
      ) { [weak self] result in
        self?.onElementDecoded?(result)
      }
    } catch {
      onElementDecoded(.failure(error))
    }
  }

  // MARK: - <StreamDelegate>

  /// Handle stream events.
  @objc public func stream(_ stream: Stream, handle eventCode: Stream.Event) {
    dispatchPrecondition(condition: .onQueue(queue))

    switch eventCode {
    case .hasBytesAvailable:
      readData()
    case .endEncountered:
      Self.log("Input stream end encountered.")
      onElementDecoded?(.success(nil))
    case .errorOccurred:
      guard let error = stream.streamError else {
        Self.log.error("Input stream unknown error encountered.")
        return
      }
      Self.log.error("Input stream error: \(error)")
      onElementDecoded?(.failure(error))
    default:
      Self.log("Input stream unhandled event code: \(eventCode)")
      break
    }
  }
}

// MARK: - StreamReader Buffer

extension StreamHandler {
  /// Buffer which processes input stream data to parse tokens.
  private enum Buffer {
    private static var log: Logger { Logger(for: Buffer.self) }

    /// Default size (byte count) of the buffer for reading data from the stream in chunks.
    static var defaultBufferSize: Int { 4_096 }

    /// Default maximum serialized size (byte count) of an element to read.
    static var defaultMaxElementSize: Int { 100_000 }

    /// The buffer is empty awaiting data to process.
    case empty

    /// `Varint` under construction assembled from the stream data.
    case pendingVarint(Data)

    /// Current `Message` under construction assembled from the stream data.
    case pendingMessage(expecting: Int, data: Data)

    mutating func extractElement(
      maxElementSize: Int,
      onElementDecoded: (Result<Element?, Error>) -> Void
    ) throws {
      switch self {
      case .empty:
        return
      case .pendingVarint(let pending):
        do {
          let (numRead, size) = try Varint.decodeFirstVarint(from: pending)
          guard size <= maxElementSize else {
            throw SerialDecodingAdaptorError.maxElementSizeExceeded(size)
          }
          self = .pendingMessage(expecting: size, data: pending.suffix(from: numRead))
        } catch Varint.DecodingError.incompleteData {
          // Varint doesn't yet have enough data, so we just need to wait for more.
          return
        }
        try extractElement(maxElementSize: maxElementSize, onElementDecoded: onElementDecoded)
      case let .pendingMessage(expecting, pending):
        guard expecting <= pending.count else { return }

        let element: Element
        if expecting == 0 {
          // The message was all defaults; nothing left to read for it.
          element = Element.init()
        } else {
          let data = pending.subdata(in: pending.startIndex..<pending.startIndex + expecting)
          element = try Element.init(serializedData: data)
        }
        onElementDecoded(.success(element))

        let remaining = pending.count - expecting
        guard remaining > 0 else {
          self = .empty
          return
        }
        self = .pendingVarint(Data(pending.suffix(remaining)))
        try extractElement(maxElementSize: maxElementSize, onElementDecoded: onElementDecoded)
      }
    }

    /// Process the input stream building a message to construct a token.
    ///
    /// - Parameters:
    ///   - inputStream: Input stream from which to read the elements.
    ///   - bufferSize: Size (byte count) of the buffer for reading from the stream.
    ///   - maxElementSize: Maximum serialized size (byte count) of an element to read.
    ///   - onElementDecoded: Handler to call with the progressive results.
    /// - Throws: An error if the token cannot be parsed or another stream error is encountered.
    mutating func read(
      from stream: InputStream,
      bufferSize: Int = Self.defaultBufferSize,
      maxElementSize: Int = Self.defaultMaxElementSize,
      onElementDecoded: (Result<Element?, Error>) -> Void
    ) throws {
      var buffer: [UInt8] = Array(repeating: 0, count: bufferSize)
      let readCount = stream.read(&buffer, maxLength: buffer.count)

      guard readCount > 0 else { return }
      let readData = Data(buffer[0..<readCount])

      switch self {
      case .empty:
        self = .pendingVarint(readData)
      case .pendingVarint(let pending):
        self = .pendingVarint(pending + readData)
      case let .pendingMessage(expecting: expecting, data: pending):
        self = .pendingMessage(expecting: expecting, data: pending + readData)
      }
      try extractElement(maxElementSize: maxElementSize, onElementDecoded: onElementDecoded)
    }
  }
}

// MARK: - StreamError

extension InputStreamMessageAdaptor {
  /// Errors specific to the input stream.
  public enum StreamError: Swift.Error {
    /// The input stream gets serviced on a run loop and the run loop failed to run.
    case runloopFailedToRun
  }
}
