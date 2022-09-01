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

/// An adaptor that binds to a data source that is serially decoded into elements.
public protocol SerialDecodingAdaptor {
  /// The type of element to decode.
  associatedtype Element

  /// Begin decoding elements from the data source.
  ///
  /// The data source should call the supplied event handler with any of the following results:
  /// - An element has been decoded. -> Result.success(element)
  /// - The input source has ended. -> Result.success(nil)
  /// - The input source has encountered an error. -> Result.failure(error)
  ///
  /// - Parameter onElementDecoded: Handler notified when an element has been decoded.
  func startDecoding(onElementDecoded: @escaping (Result<Element?, Error>) -> Void)

  /// Stop decoding elements from the data source.
  func stopDecoding()
}

/// Errors specific to the decoding adaptor.
public enum SerialDecodingAdaptorError: Error {
  /// The required size to decode an element exceeds the maximum specified.
  /// The associated value is the expected size of the element to decode.
  case maxElementSizeExceeded(Int)
}

/// Async sequence and iterator for decoding elements from a data source.
///
/// This sequence is implemented as a wrapper around an `AsyncThrowingStream` to all for future
/// flexibility.
public struct AsyncSerialDecodingSequence<Adaptor: SerialDecodingAdaptor> {
  public typealias Element = Adaptor.Element
  typealias ResultType = Result<Element?, Error>

  private var iterator: AsyncThrowingStream<Element, Error>.AsyncIterator

  /// Instantiate the sequence.
  ///
  /// - Parameter adaptor: Adaptor to an input source which provides decoded elements.
  init(_ adaptor: Adaptor) {
    let stream = AsyncThrowingStream<Element, Error> { continuation in
      adaptor.startDecoding { result in
        switch result {
        case .success(let element):
          guard let element = element else {
            continuation.finish()
            return
          }
          continuation.yield(element)
        case .failure(let error):
          continuation.finish(throwing: error)
        }
      }

      continuation.onTermination = { @Sendable _ in
        adaptor.stopDecoding()
      }
    }
    iterator = stream.makeAsyncIterator()
  }
}

// MARK: - AsyncSequence Conformance

extension AsyncSerialDecodingSequence: AsyncSequence, AsyncIteratorProtocol {
  public func makeAsyncIterator() -> Self {
    return self
  }

  public mutating func next() async throws -> Element? { try await iterator.next() }
}
