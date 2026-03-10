// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os.log

extension NetworkProvider {

  func prepareHandshakePayload(
    request: SecrecyChannelRequest
  ) async -> Result<Data, NetworkFailure> {
    let identityResult = nativeSessions.getIdentity(connectId: request.connectId)
    guard case .ok(let identity) = identityResult else {
      if case .err(let e) = identityResult {
        return .err(e.toNetworkFailure())
      }
      return .err(.connectionFailed("Unknown identity error"))
    }

    let bundleResult = await fetchServerPreKeyBundle(
      connectId: request.connectId,
      exchangeType: request.exchangeType
    )
    guard case .ok(let bundleForHandshake) = bundleResult else {
      return bundleResult.propagateErr()
    }

    let chainLimitResult = resolveChainLimit(exchangeType: request.exchangeType)
    guard case .ok(let chainLimit) = chainLimitResult else {
      return chainLimitResult.propagateErr()
    }

    let handshakeStart = NativeHandshakeInitiator.start(
      identity: identity,
      serverPreKeyBundle: bundleForHandshake,
      chainLimit: chainLimit
    )
    guard case .ok(let startInfo) = handshakeStart else {
      if case .err(let e) = handshakeStart {
        return .err(e.toNetworkFailure())
      }
      return .err(.connectionFailed("Unknown handshake start error"))
    }
    #if DEBUG
      let handshakeInitHash = SHA256.hash(data: startInfo.handshakeInit)
        .compactMap { String(format: "%02X", $0) }
        .joined()
      AppLogger.security.debug(
        "Handshake raw connectId=\(request.connectId) initLength=\(startInfo.handshakeInit.count) initHash=\(String(handshakeInitHash.prefix(16)), privacy: .private)"
      )
    #endif
    nativeSessions.storeHandshakeInitiator(
      connectId: request.connectId, initiator: startInfo.initiator)
    return .ok(startInfo.handshakeInit)
  }

  func processHandshakeRawResponse(
    handshakeAckPayload: Data,
    connectId: UInt32
  ) -> Result<Unit, NetworkFailure> {
    return finishHandshakeWithServer(
      connectId: connectId,
      handshakeResponse: handshakeAckPayload
    )
  }

  func fetchServerPreKeyBundle(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType,
    cancellationToken: CancellationToken = .none
  ) async -> Result<Data, NetworkFailure> {
    let finalToken = cancellationToken.cancelled ? CancellationToken.none : cancellationToken
    let rpcResult = await services.retryStrategy.executeRpcOperation(
      { attempt, token in
        await self.callGetServerPublicKeysRpc(
          exchangeType: exchangeType,
          cancellationToken: token
        )
      },
      operationName: "FetchServerPreKeyBundle",
      connectId: connectId,
      serviceType: .establishSecrecyChannel,
      maxRetries: nil,
      cancellationToken: finalToken
    )
    guard case .ok(let response) = rpcResult else {
      return rpcResult.propagateErr()
    }
    guard !response.serverPrekeyBundle.isEmpty else {
      return .err(.kyberKeyRequired())
    }

    let preKeyBundle = response.serverPrekeyBundle
    nativeSessions.storeServerPreKeyBundle(connectId: connectId, bundle: preKeyBundle)
    if !response.serverPublicKey.isEmpty {
      nativeSessions.storeServerPublicKey(
        connectId: connectId, publicKey: response.serverPublicKey)
    }
    if !response.serverNonce.isEmpty {
      if response.serverNonce.count == AppConstants.Crypto.serverNonceBytes {
        nativeSessions.storeServerNonce(connectId: connectId, nonce: response.serverNonce)
      } else {
        nativeSessions.clearServerNonce(connectId: connectId)
      }
    } else {
      nativeSessions.clearServerNonce(connectId: connectId)
    }
    return .ok(preKeyBundle)
  }

  private func finishHandshakeWithServer(
    connectId: UInt32,
    handshakeResponse: Data
  ) -> Result<Unit, NetworkFailure> {
    let initiatorResult = nativeSessions.getHandshakeInitiator(connectId: connectId)
    guard case .ok(let initiator) = initiatorResult else {
      return .err(.protocolStateMismatch("No handshake initiator found"))
    }

    let finishResult = NativeHandshakeInitiator.finish(
      initiator: initiator,
      handshakeResponse: handshakeResponse
    )
    guard case .ok(let session) = finishResult else {
      if case .err(let e) = finishResult {
        return .err(e.toNetworkFailure())
      }
      return .err(.connectionFailed("Unknown handshake finish error"))
    }
    nativeSessions.store(connectId: connectId, session: session)
    nativeSessions.removeHandshakeInitiator(connectId: connectId)
    return .ok(.value)
  }

  private func resolveChainLimit(exchangeType: PubKeyExchangeType) -> Result<
    UInt32, NetworkFailure
  > {
    switch exchangeType {
    case .initialHandshake:
      return .ok(1000)
    case .dataCenterEphemeralConnect:
      return .ok(1000)
    case .serverStreaming:
      return .ok(1000)
    case .deviceToDevice:
      return .ok(1000)
    }
  }

  private func callGetServerPublicKeysRpc(
    exchangeType: PubKeyExchangeType,
    cancellationToken: CancellationToken
  ) async -> Result<ServerPublicKeysResponse, NetworkFailure> {
    do {
      let service = try rpcServiceManager.getSecrecyChannelService()
      let result = await service.getServerPublicKeys(
        exchangeType: exchangeType,
        cancellationToken: cancellationToken
      )
      guard let response = result.ok() else {
        let rpcError = result.unwrapErr()
        if rpcError.isTransient {
          return .err(.dataCenterNotResponding(rpcError.logDescription))
        }
        return .err(.connectionFailed(rpcError.logDescription))
      }
      return .ok(response)
    } catch {
      return .err(error.toNetworkFailure())
    }
  }
}

extension NetworkFailure {

  static func kyberKeyRequired() -> NetworkFailure {
    NetworkFailure(
      failureType: .kyberKeyRequired,
      message: "Server returned empty prekey bundle"
    )
  }
}
