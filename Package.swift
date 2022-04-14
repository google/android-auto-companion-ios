// swift-tools-version:5.3

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

import PackageDescription

// Version 1.2.0
let package = Package(
  name: "AndroidAutoCompanion",
  platforms: [
    .iOS(.v12)
  ],
  products: [
    .library(
      name: "AndroidAutoConnectedDeviceManager",
      targets: ["AndroidAutoConnectedDeviceManager"]),
    .library(
      name: "AndroidAutoConnectedDeviceManagerMocks",
      targets: ["AndroidAutoConnectedDeviceManagerMocks"]),
  ],
  dependencies: [
    .package(
      name: "SwiftProtobuf",
      url: "https://github.com/apple/swift-protobuf.git",
      from: "1.18.0"),
  ],
  targets: [
    .binaryTarget(
      name: "AndroidAutoUKey2Wrapper",
      path: "Binary/AndroidAutoUKey2Wrapper.xcframework"),
    .target(
      name: "AndroidAutoLogger",
      dependencies: []),
    .target(
      name: "AndroidAutoCoreBluetoothProtocols",
      dependencies: ["AndroidAutoConnectedDeviceTransport"]),
    .target(
      name: "AndroidAutoCompanionProtos",
      dependencies: ["SwiftProtobuf"]),
    .target(
      name: "AndroidAutoTrustAgentProtos",
      dependencies: ["SwiftProtobuf"]),
    .target(
      name: "AndroidAutoMessageStream",
      dependencies: [
        "AndroidAutoCompanionProtos",
        "AndroidAutoConnectedDeviceTransport",
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoLogger",
        "SwiftProtobuf",
      ]),
    .target(
      name: "AndroidAutoSecureChannel",
      dependencies: [
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoMessageStream",
        "AndroidAutoUKey2Wrapper",
      ]),
    .target(
      name: "AndroidAutoConnectedDeviceManager",
      dependencies: [
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoMessageStream",
        "AndroidAutoSecureChannel",
        "AndroidAutoTrustAgentProtos",
      ]),
    .target(
      name: "AndroidAutoConnectedDeviceManagerMocks",
      dependencies: [
        "AndroidAutoConnectedDeviceManager",
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoCoreBluetoothProtocolsMocks",
        "AndroidAutoSecureChannel",
      ]),
    .target(
      name: "AndroidAutoConnectedDeviceTransport",
      dependencies: ["AndroidAutoLogger"]),
    .target(
      name: "AndroidAutoConnectedDeviceTransportFakes",
      dependencies: ["AndroidAutoConnectedDeviceTransport"]),
    .target(
      name: "AndroidAutoCoreBluetoothProtocolsMocks",
      dependencies: ["AndroidAutoCoreBluetoothProtocols"]),
    .testTarget(
      name: "AndroidAutoLoggerTests",
      dependencies: ["AndroidAutoLogger"]),
    .testTarget(
      name: "AndroidAutoMessageStreamTests",
      dependencies: [
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoCoreBluetoothProtocolsMocks",
        "AndroidAutoMessageStream",
      ]),
    .testTarget(
      name: "AndroidAutoSecureChannelTests",
      dependencies: [
        "AndroidAutoConnectedDeviceTransport",
        "AndroidAutoConnectedDeviceTransportFakes",
        "AndroidAutoMessageStream",
        "AndroidAutoSecureChannel",
        "AndroidAutoUKey2Wrapper",
      ]),
    .testTarget(
      name: "AndroidAutoConnectedDeviceManagerTests",
      dependencies: [
        "AndroidAutoConnectedDeviceManager",
        "AndroidAutoConnectedDeviceManagerMocks",
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoCoreBluetoothProtocolsMocks",
        "AndroidAutoSecureChannel",
      ]),
    .testTarget(
      name: "AndroidAutoConnectedDeviceTransportTests",
      dependencies: [
        "AndroidAutoConnectedDeviceTransport",
        "AndroidAutoConnectedDeviceTransportFakes",
      ]),
  ]
)
