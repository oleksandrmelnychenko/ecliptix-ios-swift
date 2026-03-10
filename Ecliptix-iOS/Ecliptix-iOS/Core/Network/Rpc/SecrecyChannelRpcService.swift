// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os.log

final class SecrecyChannelRpcService {

  private let transport: EventGatewayTransport

  init(transport: EventGatewayTransport) {
    self.transport = transport
  }

  func establishChannelRaw(
    connectId: UInt32,
    handshakePayload: Data,
    exchangeType: PubKeyExchangeType,
    cancellationToken: CancellationToken = .none
  ) async -> Result<Data, RpcError> {
    AppLogger.security.info(
      "SecrecyChannel: establishRaw start exchangeType=\(String(describing: exchangeType), privacy: .public), payloadSize=\(handshakePayload.count, privacy: .public)"
    )
    let result = await transport.unaryRaw(
      serviceType: .establishSecrecyChannel,
      rawPayload: handshakePayload,
      connectId: connectId,
      exchangeType: exchangeType
    )
    switch result {
    case .ok(let response):
      AppLogger.security.info(
        "SecrecyChannel: establishRaw success exchangeType=\(String(describing: exchangeType), privacy: .public), responseSize=\(response.payload.count, privacy: .public)"
      )
      return .ok(response.payload)
    case .err(let error):
      AppLogger.security.error(
        "SecrecyChannel: establishRaw RPC failed exchangeType=\(String(describing: exchangeType), privacy: .public), error=\(error.logDescription, privacy: .public)"
      )
      return .err(error)
    }
  }

  func getServerPublicKeys(
    exchangeType: PubKeyExchangeType,
    cancellationToken: CancellationToken = .none
  ) async -> Result<ServerPublicKeysResponse, RpcError> {
    AppLogger.security.info(
      "SecrecyChannel: getServerPublicKeys start exchangeType=\(String(describing: exchangeType), privacy: .public)"
    )
    let request = ProtoServerPublicKeysRequest()
    let result = await transport.unary(
      serviceType: .getServerPublicKeys,
      payload: request,
      exchangeType: exchangeType
    )
    switch result {
    case .ok(let response):
      let protoResponse: ProtoServerPublicKeysResponse
      do {
        protoResponse = try ProtoServerPublicKeysResponse(serializedBytes: response.payload)
      } catch {
        AppLogger.security.error(
          "SecrecyChannel: getServerPublicKeys deserialize failed, error=\(error.localizedDescription, privacy: .public)"
        )
        return .err(
          .deserializationFailed("ServerPublicKeysResponse: \(error.localizedDescription)"))
      }

      let swiftResponse = ServerPublicKeysResponse(
        serverPrekeyBundle: protoResponse.serverPrekeyBundle,
        serverPublicKey: protoResponse.serverPublicKey,
        serverNonce: protoResponse.serverNonce
      )
      AppLogger.security.info(
        "SecrecyChannel: getServerPublicKeys success, bundleSize=\(swiftResponse.serverPrekeyBundle.count, privacy: .public)"
      )
      return .ok(swiftResponse)
    case .err(let error):
      AppLogger.security.error(
        "SecrecyChannel: getServerPublicKeys RPC failed exchangeType=\(String(describing: exchangeType), privacy: .public), error=\(error.logDescription, privacy: .public)"
      )
      return .err(error)
    }
  }
}

struct ServerPublicKeysResponse {

  let serverPrekeyBundle: Data
  let serverPublicKey: Data
  let serverNonce: Data

  init(serverPrekeyBundle: Data, serverPublicKey: Data, serverNonce: Data) {
    self.serverPrekeyBundle = serverPrekeyBundle
    self.serverPublicKey = serverPublicKey
    self.serverNonce = serverNonce
  }
}
