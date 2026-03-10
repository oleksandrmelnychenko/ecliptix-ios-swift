// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

enum GatewayTransportFactory {

  static func buildSecureCarrier(
    rawPayload: Data
  ) -> EventEnvelope {
    var envelope = EventEnvelope()
    envelope.payload = rawPayload
    return envelope
  }

  static func buildEnvelope(
    route: GatewayRoute,
    payload: some SwiftProtobuf.Message,
    metadataProvider: MetadataProvider,
    connectId: UInt32? = nil,
    correlationId: String = UUID().uuidString,
    idempotencyKey: String = UUID().uuidString,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) throws -> EventEnvelope {
    var identity = EventIdentity()
    identity.eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    identity.eventType = route.eventType
    identity.context = route.context
    identity.correlationID = correlationId
    identity.partitionKey = metadataProvider.deviceId.uuidString
    identity.deliveryKind = route.deliveryKind
    var clientCtx = ClientContext()
    clientCtx.locale = metadataProvider.culture
    clientCtx.applicationInstanceID = metadataProvider.appInstanceId.protobufBytes
    clientCtx.deviceID = metadataProvider.deviceId.protobufBytes
    clientCtx.idempotencyKey = idempotencyKey
    clientCtx.platform = metadataProvider.platform
    var security = SecurityContext()
    if let connectId {
      security.connectID = UInt64(connectId)
    }
    security.keyExchangeContext = exchangeType.rawStringValue
    security.clientTimestamp = Int64(Date().timeIntervalSince1970)
    var metadata = EventMetadata()
    metadata.identity = identity
    metadata.client = clientCtx
    metadata.security = security
    var envelope = EventEnvelope()
    envelope.metadata = metadata
    envelope.payload = try payload.serializedData()
    return envelope
  }

  static func buildEnvelopeRaw(
    route: GatewayRoute,
    rawPayload: Data,
    metadataProvider: MetadataProvider,
    connectId: UInt32? = nil,
    correlationId: String = UUID().uuidString,
    idempotencyKey: String = UUID().uuidString,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) -> EventEnvelope {
    var identity = EventIdentity()
    identity.eventID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    identity.eventType = route.eventType
    identity.context = route.context
    identity.correlationID = correlationId
    identity.partitionKey = metadataProvider.deviceId.uuidString
    identity.deliveryKind = route.deliveryKind
    var clientCtx = ClientContext()
    clientCtx.locale = metadataProvider.culture
    clientCtx.applicationInstanceID = metadataProvider.appInstanceId.protobufBytes
    clientCtx.deviceID = metadataProvider.deviceId.protobufBytes
    clientCtx.idempotencyKey = idempotencyKey
    clientCtx.platform = metadataProvider.platform
    var security = SecurityContext()
    if let connectId {
      security.connectID = UInt64(connectId)
    }
    security.keyExchangeContext = exchangeType.rawStringValue
    security.clientTimestamp = Int64(Date().timeIntervalSince1970)
    var metadata = EventMetadata()
    metadata.identity = identity
    metadata.client = clientCtx
    metadata.security = security
    var envelope = EventEnvelope()
    envelope.metadata = metadata
    envelope.payload = rawPayload
    return envelope
  }

  static func mapOutcome(_ metadata: EventMetadata?) -> RpcError? {
    guard let outcome = metadata?.outcome,
      outcome.status.uppercased() == "ERROR"
    else {
      return nil
    }

    let code = outcome.errorCode.isEmpty ? "UNKNOWN" : outcome.errorCode
    let localizedMessage = outcome.localizedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
    return .serverError(code: code, message: localizedMessage)
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
