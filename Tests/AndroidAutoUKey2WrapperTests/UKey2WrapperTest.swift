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

import AndroidAutoUKey2Wrapper
import XCTest

/// Unit tests for `Ukey2Wrapper`.
class UKey2WrapperTest: XCTestCase {
  override func setUp() {
    super.setUp()
    continueAfterFailure = false
  }

  // MARK: - Happy path checks

  /// Verifies the initial handshake state of a `UKey2Wrapper` that has been initialized as an
  /// initiator.
  func testHandshake_initiatorInitialState() {
    let client = UKey2Wrapper(role: .initiator)
    XCTAssertEqual(client.handshakeState, .inProgress)
  }

  /// Verifies the initial handshake state of a `UKey2Wrapper` that has been initialized as an
  /// responder.
  func testHandshake_responderInitialState() {
    let server = UKey2Wrapper(role: .responder)
    XCTAssertEqual(server.handshakeState, .inProgress)
  }

  /// Verifies the initial handshake flow up to when out-of-band verification is needed.
  func testHandshake_verificationFlow() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    // Get initial message to send to server.
    var clientMessage = client.nextHandshakeMessage()
    XCTAssertNotNil(clientMessage)

    // Server receives client message.
    var result = server.parseHandshakeMessage(clientMessage!)
    XCTAssertTrue(result.isSuccessful)

    // Get message from server to send to client that it has received the message.
    let serverMesssage = server.nextHandshakeMessage()
    XCTAssertNotNil(serverMesssage)
    XCTAssertEqual(server.handshakeState, .inProgress)

    // Client parses the message from the server.
    result = client.parseHandshakeMessage(serverMesssage!)
    XCTAssertTrue(result.isSuccessful)
    XCTAssertEqual(client.handshakeState, .inProgress)

    // Client sends message to server to let it know it has received its message.
    clientMessage = client.nextHandshakeMessage()
    XCTAssertNotNil(clientMessage)
    XCTAssertEqual(client.handshakeState, .verificationNeeded)

    // Server receives confirmation from client.
    result = server.parseHandshakeMessage(clientMessage!)
    XCTAssertTrue(result.isSuccessful)
    XCTAssertEqual(server.handshakeState, .verificationNeeded)
  }

  /// Verifies that verification data matches after the handshake flow has moved into the
  /// verification needed step.
  func testHandshake_verificationStringsMatch() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    // Set up the handshake. Handshake sequence verified by testHandshake_verificationFlow.
    var clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    let serverMesssage = server.nextHandshakeMessage()
    client.parseHandshakeMessage(serverMesssage!)

    clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    // Check that resulting verification data match. Note the byte length here is arbitrary.
    let clientVerification = client.verificationData(withByteLength: 16)
    let serverVerification = server.verificationData(withByteLength: 16)

    XCTAssertNotNil(clientVerification)
    XCTAssertNotNil(serverVerification)
    XCTAssertEqual(clientVerification, serverVerification)

    // Now that the verification data has been retrieved, verify the state.
    XCTAssertEqual(server.handshakeState, .verificationInProgress)
    XCTAssertEqual(server.handshakeState, .verificationInProgress)
  }

  /// Verifies that the state of the handshake is `.finished` once verification data has been
  /// confirmed by the user.
  func testHandshake_verifyHandshake() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    // Set up the handshake. Handshake sequence verified by testHandshake_verificationFlow.
    var clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    let serverMesssage = server.nextHandshakeMessage()
    client.parseHandshakeMessage(serverMesssage!)

    clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    // Get the verification data to trigger the next state. Verification of the data is handled
    // by testHandshake_verificationStringsMatch.
    client.verificationData(withByteLength: 16)
    server.verificationData(withByteLength: 16)

    // Confirm the verification data.
    XCTAssertTrue(client.verifyHandshake())
    XCTAssertTrue(server.verifyHandshake())

    // Verify the resulting state.
    XCTAssertEqual(client.handshakeState, .finished)
    XCTAssertEqual(server.handshakeState, .finished)
  }

  /// Verifies that encoded messages from the client can be decoded by the server.
  func testEncodeDecryptFromClientToServer() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    setUpClientServerHandshake(client: client, server: server)

    assertCommunication(from: client, to: server)
  }

  /// Verifies that encoded messages from the server can be decoded by the client.
  func testEncodeDecryptFromServerToClient() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    setUpClientServerHandshake(client: client, server: server)

    assertCommunication(from: server, to: client)
  }

  /// Verifies that the session key generated by the client and server are the same.
  func testUniqueSessionKeyMatches() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    setUpClientServerHandshake(client: client, server: server)

    XCTAssertNotNil(client.uniqueSessionKey)
    XCTAssertNotNil(server.uniqueSessionKey)
    XCTAssertEqual(client.uniqueSessionKey, server.uniqueSessionKey)
  }

  // MARK: - Error checks

  /// Verifies that calling an encode before completing the handshake returns `nil`.
  func testEncodeBeforeHandshakeCompletesReturnsNil_initiator() {
    let client = UKey2Wrapper(role: .initiator)
    let messageToEncode = "message".data(using: .utf8)!

    XCTAssertNil(client.encode(messageToEncode))
    XCTAssertNotNil(client.lastHandshakeError)
  }

  /// Verifies that calling a decode before completing the handshake returns `nil`.
  func testDecodeBeforeHandshakeCompletesReturnsNil_initiator() {
    let client = UKey2Wrapper(role: .initiator)
    let messageToDecode = "message".data(using: .utf8)!

    XCTAssertNil(client.decode(messageToDecode))
    XCTAssertNotNil(client.lastHandshakeError)
  }

  /// Verifies that calling an encode before completing the handshake returns `nil`.
  func testEncodeBeforeHandshakeCompletesReturnsNil_responder() {
    let server = UKey2Wrapper(role: .responder)
    let messageToEncode = "message".data(using: .utf8)!

    XCTAssertNil(server.encode(messageToEncode))
    XCTAssertNotNil(server.lastHandshakeError)
  }

  /// Verifies that calling a decode before completing the handshake returns `nil`.
  func testDecodeBeforeHandshakeCompletesReturnsNil_responder() {
    let server = UKey2Wrapper(role: .responder)
    let messageToDecode = "message".data(using: .utf8)!

    XCTAssertNil(server.decode(messageToDecode))
    XCTAssertNotNil(server.lastHandshakeError)
  }

  // MARK: - SaveSession tests.

  /// Assert that the UKey2Wrapper can still encode and decode messages properly after a
  /// recreating from a saved session.
  func testSaveSession_CanStillCommunicateAfterRestoration() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    setUpClientServerHandshake(client: client, server: server)

    let clientSavedSession = client.saveSession()
    let serverSavedSession = server.saveSession()

    XCTAssertNotNil(clientSavedSession)
    XCTAssertNotNil(serverSavedSession)

    let restoredClient = UKey2Wrapper(savedSession: clientSavedSession!)
    let restoredServer = UKey2Wrapper(savedSession: serverSavedSession!)

    XCTAssertNotNil(restoredClient)
    XCTAssertNotNil(restoredServer)

    assertCommunication(from: restoredClient!, to: restoredServer!)
    assertCommunication(from: restoredClient!, to: restoredServer!)
  }

  /// Assert that the UKey2Wrapper still retains the same session key after recreating from a
  /// saved session.
  func testSaveSession_HasSameSessionKey() {
    let client = UKey2Wrapper(role: .initiator)
    let server = UKey2Wrapper(role: .responder)

    setUpClientServerHandshake(client: client, server: server)

    let previousClientKey = client.uniqueSessionKey
    let previousServerKey = server.uniqueSessionKey

    XCTAssertNotNil(previousClientKey)
    XCTAssertNotNil(previousServerKey)

    let clientSavedSession = client.saveSession()
    let serverSavedSession = server.saveSession()
    let restoredClient = UKey2Wrapper(savedSession: clientSavedSession!)
    let restoredServer = UKey2Wrapper(savedSession: serverSavedSession!)

    XCTAssertEqual(restoredClient!.uniqueSessionKey, previousClientKey)
    XCTAssertEqual(restoredServer!.uniqueSessionKey, previousServerKey)
  }

  // MARK: - Testing utility methods

  /// Runs through the complete flow of a handshake between the given client and server. After
  /// calling this method, both client and server can begin using encoding/decoding methods.
  ///
  /// - Parameters:
  ///   - client: The client / initiator.
  ///   - server: The server / responder.
  private func setUpClientServerHandshake(client: UKey2Wrapper, server: UKey2Wrapper) {
    // Set up the handshake. Handshake sequence verified by testHandshake_verificationFlow.
    var clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    let serverMesssage = server.nextHandshakeMessage()
    client.parseHandshakeMessage(serverMesssage!)

    clientMessage = client.nextHandshakeMessage()
    server.parseHandshakeMessage(clientMessage!)

    // Get the verification data to trigger the next state. Verification of the data is handled
    // by testHandshake_verificationStringsMatch.
    client.verificationData(withByteLength: 16)
    server.verificationData(withByteLength: 16)

    // Verify the handshake to finish. Verified by testHandshake_verifyHandshake.
    client.verifyHandshake()
    server.verifyHandshake()
  }

  /// Verifies that messages can be decoded properly from the given initiator to the given
  /// receiver.
  private func assertCommunication(from initiator: UKey2Wrapper, to receiver: UKey2Wrapper) {
    let messageText = "message_to_server"
    let messageToEncode = initiator.encode(Data(messageText.utf8))
    XCTAssertNotNil(messageToEncode)

    let decodedMessage = receiver.decode(messageToEncode!)
    XCTAssertNotNil(decodedMessage)

    // Now verify the contents of the decoded message.
    XCTAssertEqual(String(data: decodedMessage!, encoding: .utf8), messageText)
  }
}
