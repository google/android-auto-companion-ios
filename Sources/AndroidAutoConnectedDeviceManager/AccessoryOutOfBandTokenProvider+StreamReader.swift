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
@_implementationOnly import AndroidAutoCompanionProtos

#if canImport(ExternalAccessory)

  private typealias OutOfBandAssociationToken = Com_Google_Companionprotos_OutOfBandAssociationToken

  // MARK: - StreamReader

  extension AccessoryOutOfBandTokenProvider {
    /// Read out of band tokens from an input stream.
    final class StreamReader: NSObject {
      private static let log = Logger(for: StreamReader.self)

      /// The input stream from which to read the tokens.
      private let stream: InputStream

      /// Buffer which processes the input stream data to construct the token.
      private var buffer: Buffer<Int32> = .empty

      /// Handler which receives the tokens read from the stream.
      private var handler: (OutOfBandToken) -> Void

      /// Indicates whether the stream is open.
      var isOpen: Bool { stream.streamStatus == .open }

      /// Indicates whether this reader is valid.
      var isValid = true

      /// Initializes the reader with the specified input stream.
      ///
      /// - Parameters:
      ///   - stream: Input stream from which to read the tokens.
      ///   - handler: Handler to process tokens that are read.
      init(stream: InputStream, handler: @escaping (OutOfBandToken) -> Void) {
        Self.log("Opening input stream.")

        self.stream = stream
        self.handler = handler

        super.init()

        stream.delegate = self
        stream.open()
        stream.schedule(in: .current, forMode: .common)
      }

      /// Invalidate the reader.
      ///
      /// Closes the underlying stream and tears down the stream support.
      ///
      /// This reader will no longer be usable once invalidated.
      func invalidate() {
        guard isValid else { return }

        isValid = false
        stream.delegate = nil
        stream.remove(from: .current, forMode: .common)
        stream.close()
      }

      /// Service the input stream as long as there is data to be read.
      private func read() {
        Self.log("Reading bytes from stream.")

        guard isOpen, stream.hasBytesAvailable else { return }

        do {
          while isOpen, stream.hasBytesAvailable {
            try buffer.read(from: stream)
            if let token = buffer.token {
              buffer = .empty
              handler(token)
            }
          }
        } catch {
          Self.log.error("Error reading the token from the stream: \(error.localizedDescription)")
        }
      }

      /// Reset the buffer to start processing new tokens.
      func reset() {
        buffer.reset()
      }
    }
  }

  // MARK: - StreamReader StreamDelegate

  extension AccessoryOutOfBandTokenProvider.StreamReader: StreamDelegate {
    /// Handle stream events.
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
      switch eventCode {
      case .hasBytesAvailable:
        read()
      case .endEncountered:
        Self.log.error("Stream end encountered.")
        invalidate()
      case .errorOccurred:
        Self.log.error("Stream error: \(stream.streamError?.localizedDescription ?? "Unknown")")
        invalidate()
      default:
        Self.log.info("Received unhandled stream event: \(eventCode)")
      }
    }
  }

  // MARK: - StreamReader Buffer

  extension AccessoryOutOfBandTokenProvider.StreamReader {
    /// Buffer which processes input stream data to parse tokens.
    private enum Buffer<SizeType: FixedWidthInteger> {
      private static var log: Logger { Logger(for: Buffer<SizeType>.self) }

      /// Size (bytes) of the buffer for reading data from the stream in chunks.
      private static var bufferSize: Int { 1_024 }

      /// The buffer is empty awaiting data to process.
      case empty

      /// Current message under construction assembled from the stream data.
      case message([UInt8])

      /// A parsed token from a complete message.
      case token(OutOfBandToken)

      /// A token (if any) read from the stream.
      var token: OutOfBandToken? {
        if case let .token(token) = self {
          return token
        } else {
          return nil
        }
      }

      /// Reset the buffer to empty, clearing its token.
      mutating func reset() {
        self = .empty
      }

      /// Process the input stream building a message to construct a token.
      ///
      /// - Parameter stream: The stream from which to read the message.
      /// - Throws: An error if the token cannot be parsed or another stream error is encountered.
      mutating func read(from stream: InputStream) throws {
        switch self {
        case .empty, .token(_):
          try readMessage(from: stream, pending: [])
        case let .message(pending):
          try readMessage(from: stream, pending: pending)
        }
      }

      private mutating func readMessage(
        from stream: InputStream,
        pending: [UInt8]
      ) throws {
        Self.log("Read message pending: \(pending.count)")
        let maxLength = Self.bufferSize
        Self.log("Read message maxLength: \(maxLength)")
        var buffer: [UInt8] = Array(repeating: 0, count: maxLength)
        let readCount = stream.read(&buffer, maxLength: buffer.count)
        guard readCount > 0 else { return }

        Self.log("Read message readCount: \(readCount)")
        let message = pending + Array(buffer[0..<readCount])
        Self.log("Read message current message length: \(message.count)")

        if stream.hasBytesAvailable {
          Self.log("Waiting for more data.")
          self = .message(message)
        } else {
          Self.log("Parsing token.")
          let messageData = Data(message)
          let token = try OutOfBandAssociationToken(serializedData: messageData)
          self = .token(token)
        }
      }
    }
  }

#endif  // ExternalAccessory
