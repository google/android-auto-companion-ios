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

let package = Package(
  name: "AndroidAutoCompanion",
  platforms: [
    .iOS(.v12)
  ],
  products: [
    .library(
      name: "AndroidAutoConnectedDeviceManager",
      targets: ["AndroidAutoConnectedDeviceManager"])
  ],
  dependencies: [
    .package(
      name: "SwiftProtobuf",
      url: "https://github.com/apple/swift-protobuf.git",
      from: "1.6.0")
  ],
  targets: [
    .target(
      name: "AndroidAutoLogger",
      dependencies: []),
    .target(
      name: "AndroidAutoCoreBluetoothProtocols",
      dependencies: []),
    .target(
      name: "AndroidAutoMessageStream",
      dependencies: [
        "AndroidAutoConnectedDeviceTransport",
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoLogger",
        "SwiftProtobuf",
      ]),
    .target(
      name: "AndroidAutoUKey2Wrapper",
      dependencies: []),
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
        "AndroidAutoUKey2Wrapper",
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
      name: "AndroidAutoUKey2WrapperTests",
      dependencies: [
        "AndroidAutoUKey2Wrapper"
      ]),
    .testTarget(
      name: "AndroidAutoSecureChannelTests",
      dependencies: [
        "AndroidAutoCoreBluetoothProtocols",
        "AndroidAutoCoreBluetoothProtocolsMocks",
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
      ]),
  ]
)
