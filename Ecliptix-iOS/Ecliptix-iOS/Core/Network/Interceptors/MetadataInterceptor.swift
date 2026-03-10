// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class MetadataInterceptor {

  private let metadataProvider: MetadataProvider

  init(metadataProvider: MetadataProvider) {
    self.metadataProvider = metadataProvider
  }

  func injectMetadata(
    into headers: inout [String: String],
    exchangeType: PubKeyExchangeType? = nil,
    connectId: UInt32? = nil
  ) {
    headers["application-identifier"] = metadataProvider.appInstanceId.uuidString
    headers["d-identifier"] = metadataProvider.deviceId.uuidString
    headers["platform"] = metadataProvider.platform
    headers["lang"] = metadataProvider.culture
    if let exchangeType = exchangeType {
      headers["c-context-id"] = exchangeType.rawStringValue
      headers["exchange-type"] = exchangeType.rawStringValue
    }
    if let connectId = connectId {
      headers["x-connect-id"] = String(connectId)
    }
  }
}

struct GrpcMetadata {

  static func generate(
    metadataProvider: MetadataProvider,
    exchangeType: PubKeyExchangeType? = nil,
    connectId: UInt32? = nil
  ) -> [String: String] {
    var headers: [String: String] = [:]
    MetadataInterceptor(metadataProvider: metadataProvider).injectMetadata(
      into: &headers,
      exchangeType: exchangeType,
      connectId: connectId
    )
    return headers
  }
}

extension PubKeyExchangeType {

  fileprivate var rawStringValue: String {
    switch self {
    case .initialHandshake: return "InitialHandshake"
    case .dataCenterEphemeralConnect: return "DataCenterEphemeralConnect"
    case .serverStreaming: return "ServerStreaming"
    case .deviceToDevice: return "DeviceToDevice"
    }
  }
}
