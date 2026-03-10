// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import SwiftProtobuf
import os

@available(macOS 15.0, iOS 18.0, watchOS 11.0, tvOS 18.0, visionOS 2.0, *)
private struct GatewayServiceClient<Transport: GRPCCore.ClientTransport> {

  private let base: Ecliptix_Transport_Gateway_EventGateway.Client<Transport>

  init(wrapping client: GRPCCore.GRPCClient<Transport>) {
    self.base = .init(wrapping: client)
  }

  func unary<Result>(
    request: GRPCCore.ClientRequest<EventEnvelope>,
    serializer: some GRPCCore.MessageSerializer<EventEnvelope>,
    deserializer: some GRPCCore.MessageDeserializer<EventEnvelope>,
    options: GRPCCore.CallOptions,
    onResponse handleResponse: @Sendable @escaping (GRPCCore.ClientResponse<EventEnvelope>)
      async throws -> Result
  ) async throws -> Result where Result: Sendable {
    try await base.unary(
      request: request,
      serializer: serializer,
      deserializer: deserializer,
      options: options,
      onResponse: handleResponse
    )
  }

  func serverStream<Result>(
    request: GRPCCore.ClientRequest<EventEnvelope>,
    serializer: some GRPCCore.MessageSerializer<EventEnvelope>,
    deserializer: some GRPCCore.MessageDeserializer<EventEnvelope>,
    options: GRPCCore.CallOptions,
    onResponse handleResponse: @Sendable @escaping (GRPCCore.StreamingClientResponse<EventEnvelope>)
      async throws -> Result
  ) async throws -> Result where Result: Sendable {
    try await base.serverStream(
      request: request,
      serializer: serializer,
      deserializer: deserializer,
      options: options,
      onResponse: handleResponse
    )
  }
}

actor EventGatewayTransport {

  private let channelProvider: GrpcChannelProvider
  private let metadataProvider: MetadataProvider
  private let requestTimeout: TimeInterval
  private var callOptions: GRPCCore.CallOptions {
    var opts = GRPCCore.CallOptions.defaults
    opts.timeout = .seconds(Int(requestTimeout))
    return opts
  }

  private var streamCallOptions: GRPCCore.CallOptions {
    GRPCCore.CallOptions.defaults
  }

  init(
    channelProvider: GrpcChannelProvider,
    metadataProvider: MetadataProvider,
    requestTimeout: TimeInterval = 30.0
  ) {
    self.channelProvider = channelProvider
    self.metadataProvider = metadataProvider
    self.requestTimeout = requestTimeout
  }

  func requestEnvelope(
    serviceType: RpcServiceType,
    rawPayload: Data,
    connectId: UInt32? = nil,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) throws -> EventEnvelope {
    guard let route = GatewayRouteCatalog.route(for: serviceType) else {
      throw NSError(
        domain: "EventGatewayTransport",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "No route for service type: \(serviceType.rawValue)"]
      )
    }
    return GatewayTransportFactory.buildEnvelopeRaw(
      route: route,
      rawPayload: rawPayload,
      metadataProvider: metadataProvider,
      connectId: connectId,
      exchangeType: exchangeType
    )
  }

  func unary(
    serviceType: RpcServiceType,
    payload: some SwiftProtobuf.Message,
    connectId: UInt32? = nil,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) async -> Result<EventEnvelope, RpcError> {
    guard let route = GatewayRouteCatalog.route(for: serviceType) else {
      return .err(.unexpected("No route for service type: \(serviceType.rawValue)"))
    }

    let routeLabel = String(describing: route.eventType)
    AppLogger.network.debug(
      "Gateway unary: service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), exchange=\(exchangeType.rawStringValue, privacy: .public)"
    )
    do {
      let payloadData = try payload.serializedData()
      let envelope =
        payload is ProtoSecureEnvelope && connectId != nil
        ? GatewayTransportFactory.buildSecureCarrier(rawPayload: payloadData)
        : GatewayTransportFactory.buildEnvelopeRaw(
          route: route,
          rawPayload: payloadData,
          metadataProvider: metadataProvider,
          connectId: connectId,
          exchangeType: exchangeType
        )
      let grpcClient = try await channelProvider.getClient()
      let gateway = GatewayServiceClient(wrapping: grpcClient)
      let request = GRPCCore.ClientRequest(
        message: envelope,
        metadata: buildGrpcMetadata(exchangeType: exchangeType, connectId: connectId)
      )
      let response = try await gateway.unary(
        request: request,
        serializer: GRPCProtobuf.ProtobufSerializer<EventEnvelope>(),
        deserializer: GRPCProtobuf.ProtobufDeserializer<EventEnvelope>(),
        options: callOptions
      ) { (responseValue: GRPCCore.ClientResponse<EventEnvelope>) throws -> EventEnvelope in
        try responseValue.message
      }
      if let rpcError = GatewayTransportFactory.mapOutcome(response.metadata) {
        AppLogger.network.warning(
          "Gateway unary: server outcome failure service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(rpcError)
      }
      AppLogger.network.debug(
        "Gateway unary: success service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public)"
      )
      return .ok(response)
    } catch let rpcError as RPCError {
      AppLogger.network.warning(
        "Gateway unary: RPCError service=\(serviceType.rawValue, privacy: .public), code=\(String(describing: rpcError.code), privacy: .public), message=\(rpcError.message, privacy: .public)"
      )
      return .err(.grpcError(code: String(describing: rpcError.code), message: rpcError.message))
    } catch {
      AppLogger.network.error(
        "Gateway unary: unexpected error service=\(serviceType.rawValue, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.unexpected(error.localizedDescription))
    }
  }

  func unaryRaw(
    serviceType: RpcServiceType,
    rawPayload: Data,
    connectId: UInt32? = nil,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) async -> Result<EventEnvelope, RpcError> {
    guard let route = GatewayRouteCatalog.route(for: serviceType) else {
      return .err(.unexpected("No route for service type: \(serviceType.rawValue)"))
    }

    let routeLabel = String(describing: route.eventType)
    AppLogger.network.debug(
      "Gateway unaryRaw: service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), exchange=\(exchangeType.rawStringValue, privacy: .public)"
    )
    let envelope = GatewayTransportFactory.buildEnvelopeRaw(
      route: route,
      rawPayload: rawPayload,
      metadataProvider: metadataProvider,
      connectId: connectId,
      exchangeType: exchangeType
    )
    do {
      let grpcClient = try await channelProvider.getClient()
      let gateway = GatewayServiceClient(wrapping: grpcClient)
      let request = GRPCCore.ClientRequest(
        message: envelope,
        metadata: buildGrpcMetadata(exchangeType: exchangeType, connectId: connectId)
      )
      let response = try await gateway.unary(
        request: request,
        serializer: GRPCProtobuf.ProtobufSerializer<EventEnvelope>(),
        deserializer: GRPCProtobuf.ProtobufDeserializer<EventEnvelope>(),
        options: callOptions
      ) { (responseValue: GRPCCore.ClientResponse<EventEnvelope>) throws -> EventEnvelope in
        try responseValue.message
      }
      if let rpcError = GatewayTransportFactory.mapOutcome(response.metadata) {
        AppLogger.network.warning(
          "Gateway unaryRaw: server outcome failure service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(rpcError)
      }
      AppLogger.network.debug(
        "Gateway unaryRaw: success service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), payloadBytes=\(response.payload.count, privacy: .public)"
      )
      return .ok(response)
    } catch let rpcError as RPCError {
      AppLogger.network.warning(
        "Gateway unaryRaw: RPCError service=\(serviceType.rawValue, privacy: .public), code=\(String(describing: rpcError.code), privacy: .public), message=\(rpcError.message, privacy: .public)"
      )
      return .err(.grpcError(code: String(describing: rpcError.code), message: rpcError.message))
    } catch {
      AppLogger.network.error(
        "Gateway unaryRaw: unexpected error service=\(serviceType.rawValue, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.unexpected(error.localizedDescription))
    }
  }

  func serverStream(
    serviceType: RpcServiceType,
    payload: some SwiftProtobuf.Message,
    connectId: UInt32? = nil,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect,
    onMessage: @escaping (EventEnvelope) async -> Void
  ) async -> Result<Unit, RpcError> {
    guard let route = GatewayRouteCatalog.route(for: serviceType) else {
      return .err(.unexpected("No route for service type: \(serviceType.rawValue)"))
    }

    let routeLabel = String(describing: route.eventType)
    AppLogger.network.debug(
      "Gateway stream: start service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public), exchange=\(exchangeType.rawStringValue, privacy: .public)"
    )
    do {
      let payloadData = try payload.serializedData()
      let envelope =
        payload is ProtoSecureEnvelope && connectId != nil
        ? GatewayTransportFactory.buildSecureCarrier(rawPayload: payloadData)
        : GatewayTransportFactory.buildEnvelopeRaw(
          route: route,
          rawPayload: payloadData,
          metadataProvider: metadataProvider,
          connectId: connectId,
          exchangeType: exchangeType
        )
      let grpcClient = try await channelProvider.getClient()
      let gateway = GatewayServiceClient(wrapping: grpcClient)
      let request = GRPCCore.ClientRequest(
        message: envelope,
        metadata: buildGrpcMetadata(exchangeType: exchangeType, connectId: connectId)
      )
      try await gateway.serverStream(
        request: request,
        serializer: GRPCProtobuf.ProtobufSerializer<EventEnvelope>(),
        deserializer: GRPCProtobuf.ProtobufDeserializer<EventEnvelope>(),
        options: streamCallOptions
      ) { (response: GRPCCore.StreamingClientResponse<EventEnvelope>) async throws -> Void in
        for try await message in response.messages {
          await onMessage(message)
        }
      }
      AppLogger.network.debug(
        "Gateway stream: success service=\(serviceType.rawValue, privacy: .public), route=\(routeLabel, privacy: .public)"
      )
      return .ok(Unit.value)
    } catch let rpcError as RPCError {
      AppLogger.network.warning(
        "Gateway stream: RPCError service=\(serviceType.rawValue, privacy: .public), code=\(String(describing: rpcError.code), privacy: .public), message=\(rpcError.message, privacy: .public)"
      )
      return .err(.grpcError(code: String(describing: rpcError.code), message: rpcError.message))
    } catch {
      AppLogger.network.error(
        "Gateway stream: unexpected error service=\(serviceType.rawValue, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.unexpected(error.localizedDescription))
    }
  }

  private static let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()

  private func buildGrpcMetadata(
    exchangeType: PubKeyExchangeType,
    connectId: UInt32? = nil
  ) -> GRPCCore.Metadata {
    var metadata = GRPCCore.Metadata()
    let now = Date()
    let linkUUID = UUID()
    let linkSeed = linkUUID.uuidString.replacingOccurrences(of: "-", with: "")
    let linkValue = "link-\(linkSeed.prefix(AppConstants.Otp.linkSeedPrefixLength))"
    metadata.addString(UUID().uuidString, forKey: "request-id")
    metadata.addString(Self.iso8601Formatter.string(from: now), forKey: "request-date")
    metadata.addString("", forKey: "local-ip-address")
    metadata.addString("", forKey: "public-ip-address")
    metadata.addString(metadataProvider.culture, forKey: "lang")
    metadata.addString(String(linkValue), forKey: "fetch-link")
    metadata.addString(metadataProvider.appInstanceId.uuidString, forKey: "application-identifier")
    metadata.addString(metadataProvider.deviceId.uuidString, forKey: "d-identifier")
    metadata.addString(metadataProvider.platform, forKey: "platform")
    metadata.addString(
      AppConstants.Gateway.transportTokenValue, forKey: AppConstants.Gateway.transportTokenKey)
    let exchangeValue = exchangeType.rawStringValue
    metadata.addString(exchangeValue, forKey: "c-context-id")
    metadata.addString("", forKey: "o-context-id")
    metadata.addString(exchangeValue, forKey: "exchange-type")
    if let connectId {
      metadata.addString(String(connectId), forKey: "x-connect-id")
    }
    return metadata
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
