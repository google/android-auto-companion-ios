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

// DO NOT EDIT.
// swift-format-ignore-file
//
// Generated by the Swift generator plugin for the protocol buffer compiler.
// Source: third_party/companion_protos/capabilities_exchange.proto
//
// For information on using the generated types, please see the documentation:
//   https://github.com/apple/swift-protobuf/

import Foundation
import SwiftProtobuf

// If the compiler emits an error on this type, it is because this file
// was generated by a version of the `protoc` Swift plug-in that is
// incompatible with the version of SwiftProtobuf to which you are linking.
// Please ensure that you are building against the same version of the API
// that was used to generate this file.
fileprivate struct _GeneratedWithProtocGenSwiftVersion: SwiftProtobuf.ProtobufAPIVersionCheck {
  struct _2: SwiftProtobuf.ProtobufAPIVersion_2 {}
  typealias Version = _2
}

public struct Com_Google_Companionprotos_CapabilitiesExchange {
  // SwiftProtobuf.Message conformance is added in an extension below. See the
  // `Message` and `Message+*Additions` files in the SwiftProtobuf library for
  // methods supported on all messages.

  public var supportedOobChannels: [Com_Google_Companionprotos_CapabilitiesExchange.OobChannelType] = []

  public var mobileOs: Com_Google_Companionprotos_CapabilitiesExchange.MobileOs = .unknown

  public var deviceName: String = String()

  public var unknownFields = SwiftProtobuf.UnknownStorage()

  public enum OobChannelType: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case oobChannelUnknown // = 0
    case btRfcomm // = 1
    case preAssociation // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .oobChannelUnknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .oobChannelUnknown
      case 1: self = .btRfcomm
      case 2: self = .preAssociation
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .oobChannelUnknown: return 0
      case .btRfcomm: return 1
      case .preAssociation: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public enum MobileOs: SwiftProtobuf.Enum {
    public typealias RawValue = Int
    case unknown // = 0
    case android // = 1
    case ios // = 2
    case UNRECOGNIZED(Int)

    public init() {
      self = .unknown
    }

    public init?(rawValue: Int) {
      switch rawValue {
      case 0: self = .unknown
      case 1: self = .android
      case 2: self = .ios
      default: self = .UNRECOGNIZED(rawValue)
      }
    }

    public var rawValue: Int {
      switch self {
      case .unknown: return 0
      case .android: return 1
      case .ios: return 2
      case .UNRECOGNIZED(let i): return i
      }
    }

  }

  public init() {}
}

#if swift(>=4.2)

extension Com_Google_Companionprotos_CapabilitiesExchange.OobChannelType: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Com_Google_Companionprotos_CapabilitiesExchange.OobChannelType] = [
    .oobChannelUnknown,
    .btRfcomm,
    .preAssociation,
  ]
}

extension Com_Google_Companionprotos_CapabilitiesExchange.MobileOs: CaseIterable {
  // The compiler won't synthesize support with the UNRECOGNIZED case.
  public static var allCases: [Com_Google_Companionprotos_CapabilitiesExchange.MobileOs] = [
    .unknown,
    .android,
    .ios,
  ]
}

#endif  // swift(>=4.2)

// MARK: - Code below here is support for the SwiftProtobuf runtime.

fileprivate let _protobuf_package = "com.google.companionprotos"

extension Com_Google_Companionprotos_CapabilitiesExchange: SwiftProtobuf.Message, SwiftProtobuf._MessageImplementationBase, SwiftProtobuf._ProtoNameProviding {
  public static let protoMessageName: String = _protobuf_package + ".CapabilitiesExchange"
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    1: .standard(proto: "supported_oob_channels"),
    2: .standard(proto: "mobile_os"),
    3: .standard(proto: "device_name"),
  ]

  public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {
    while let fieldNumber = try decoder.nextFieldNumber() {
      // The use of inline closures is to circumvent an issue where the compiler
      // allocates stack space for every case branch when no optimizations are
      // enabled. https://github.com/apple/swift-protobuf/issues/1034
      switch fieldNumber {
      case 1: try { try decoder.decodeRepeatedEnumField(value: &self.supportedOobChannels) }()
      case 2: try { try decoder.decodeSingularEnumField(value: &self.mobileOs) }()
      case 3: try { try decoder.decodeSingularStringField(value: &self.deviceName) }()
      default: break
      }
    }
  }

  public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {
    if !self.supportedOobChannels.isEmpty {
      try visitor.visitPackedEnumField(value: self.supportedOobChannels, fieldNumber: 1)
    }
    if self.mobileOs != .unknown {
      try visitor.visitSingularEnumField(value: self.mobileOs, fieldNumber: 2)
    }
    if !self.deviceName.isEmpty {
      try visitor.visitSingularStringField(value: self.deviceName, fieldNumber: 3)
    }
    try unknownFields.traverse(visitor: &visitor)
  }

  public static func ==(lhs: Com_Google_Companionprotos_CapabilitiesExchange, rhs: Com_Google_Companionprotos_CapabilitiesExchange) -> Bool {
    if lhs.supportedOobChannels != rhs.supportedOobChannels {return false}
    if lhs.mobileOs != rhs.mobileOs {return false}
    if lhs.deviceName != rhs.deviceName {return false}
    if lhs.unknownFields != rhs.unknownFields {return false}
    return true
  }
}

extension Com_Google_Companionprotos_CapabilitiesExchange.OobChannelType: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "OOB_CHANNEL_UNKNOWN"),
    1: .same(proto: "BT_RFCOMM"),
    2: .same(proto: "PRE_ASSOCIATION"),
  ]
}

extension Com_Google_Companionprotos_CapabilitiesExchange.MobileOs: SwiftProtobuf._ProtoNameProviding {
  public static let _protobuf_nameMap: SwiftProtobuf._NameMap = [
    0: .same(proto: "UNKNOWN"),
    1: .same(proto: "ANDROID"),
    2: .same(proto: "IOS"),
  ]
}
