// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class NetworkEncryptedRequestExecutor: @unchecked Sendable {

  private let sessionRuntime: SecureSessionRuntime
  private let rpcServiceManager: RpcServiceManager
  private let requestRegistry: NetworkProviderRequestRegistry
  private let outageState: NetworkProviderOutageState
  private let recoverSession: @Sendable (UInt32) async -> Result<Unit, String>
  private let clearConnection: @Sendable (UInt32) -> Void
  private let retryPendingRequests: @Sendable () async -> Void

  init(
    sessionRuntime: SecureSessionRuntime,
    rpcServiceManager: RpcServiceManager,
    requestRegistry: NetworkProviderRequestRegistry,
    outageState: NetworkProviderOutageState,
    recoverSession: @escaping @Sendable (UInt32) async -> Result<Unit, String>,
    clearConnection: @escaping @Sendable (UInt32) -> Void,
    retryPendingRequests: @escaping @Sendable () async -> Void
  ) {
    self.sessionRuntime = sessionRuntime
    self.rpcServiceManager = rpcServiceManager
    self.requestRegistry = requestRegistry
    self.outageState = outageState
    self.recoverSession = recoverSession
    self.clearConnection = clearConnection
    self.retryPendingRequests = retryPendingRequests
  }

  func execute(request: ServiceRequestParams) async -> Result<Unit, NetworkFailure> {
    AppLogger.network.debug(
      "Request pipeline: start service=\(request.serviceType.rawValue, privacy: .public), connectId=\(request.connectId, privacy: .public), flow=\(String(describing: request.flowType), privacy: .public), payloadBytes=\(request.plainBuffer.count, privacy: .public)"
    )
    let effectiveContext = request.requestContext ?? RpcRequestContext.createNew()
    let serviceContext = ServiceRequestContext(
      connectId: request.connectId,
      serviceType: request.serviceType,
      plainBuffer: request.plainBuffer,
      flowType: request.flowType,
      onCompleted: request.onCompleted,
      requestContext: effectiveContext,
      exchangeType: request.exchangeType
    )
    let requestKey = generateRequestKey(
      connectId: request.connectId,
      serviceType: request.serviceType,
      plainBuffer: request.plainBuffer
    )
    let shouldAllowDuplicates =
      request.allowDuplicateRequests || canServiceTypeBeDuplicated(request.serviceType)
    if let duplicateResult = tryRegisterRequest(
      key: requestKey,
      allowDuplicates: shouldAllowDuplicates,
      cancellationToken: request.cancellationToken
    ) {
      AppLogger.network.warning(
        "Request pipeline: duplicate rejected service=\(request.serviceType.rawValue, privacy: .public), connectId=\(request.connectId, privacy: .public), requestKey=\(requestKey, privacy: .public)"
      )
      return duplicateResult
    }
    defer {
      unregisterRequest(key: requestKey)
    }
    if request.cancellationToken.cancelled {
      AppLogger.network.debug(
        "Request pipeline: cancelled before execution service=\(request.serviceType.rawValue, privacy: .public), connectId=\(request.connectId, privacy: .public)"
      )
      return .err(.operationCancelled(AppConstants.Network.Request.requestCancelledBeforeExecution))
    }
    return await executeRequestWithProtocol(
      context: serviceContext,
      waitForRecovery: request.waitForRecovery,
      cancellationToken: request.cancellationToken
    )
  }

  private func executeRequestWithProtocol(
    context: ServiceRequestContext,
    waitForRecovery: Bool,
    cancellationToken: CancellationToken,
    isReinitRetry: Bool = false
  ) async -> Result<Unit, NetworkFailure> {
    if waitForRecovery && outageState.currentOutageState() {
      AppLogger.network.info(
        "Request pipeline: waiting outage recovery service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public)"
      )
      await waitForOutageRecovery()
    }

    let sessionResult = sessionRuntime.get(connectId: context.connectId)
    guard case .ok(let session) = sessionResult else {
      AppLogger.network.error(
        "Request pipeline: missing session service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public)"
      )
      return .err(
        .protocolStateMismatch(
          "\(AppConstants.Network.Request.noActiveSessionPrefix) \(context.connectId)"))
    }

    let requestEnvelopeResult = await buildRequestEnvelopePayload(context: context)
    guard case .ok(let requestEnvelopePayload) = requestEnvelopeResult else {
      AppLogger.network.warning(
        "Request pipeline: failed to build secure request envelope service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public), error=\(requestEnvelopeResult.err()?.message ?? "", privacy: .public)"
      )
      return requestEnvelopeResult.propagateErr()
    }

    let encryptResult = encryptRequestPayload(
      plainBuffer: requestEnvelopePayload,
      session: session
    )
    guard case .ok(let encryptedPayload) = encryptResult else {
      AppLogger.network.warning(
        "Request pipeline: encryption failed service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public), error=\(encryptResult.err()?.message ?? "", privacy: .public)"
      )
      return encryptResult.propagateErr()
    }
    AppLogger.network.debug(
      "Request pipeline: encrypted payload service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public), encryptedBytes=\(encryptedPayload.count, privacy: .public)"
    )
    let result: Result<Unit, NetworkFailure>
    switch context.flowType {
    case .single:
      result = await executeUnaryRpc(
        connectId: context.connectId,
        serviceType: context.serviceType,
        encryptedPayload: encryptedPayload,
        onCompleted: context.onCompleted,
        session: session,
        cancellationToken: cancellationToken
      )
    case .receiveStream:
      result = await executeStreamingRpc(
        connectId: context.connectId,
        serviceType: context.serviceType,
        encryptedPayload: encryptedPayload,
        onStreamItem: context.onCompleted,
        session: session,
        cancellationToken: cancellationToken,
        exchangeType: context.exchangeType
      )
    }
    if case .err(let failure) = result, failure.requiresReinit, !isReinitRetry {
      AppLogger.network.warning(
        "Request pipeline: server requested session re-init service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public)"
      )
      sessionRuntime.invalidateSession(connectId: context.connectId)
      let reinitResult = await recoverSession(context.connectId)
      guard reinitResult.isOk else {
        let reinitError = reinitResult.err() ?? ""
        clearConnection(context.connectId)
        AppLogger.network.error(
          "Request pipeline: re-init handshake failed service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public), error=\(reinitError, privacy: .public)"
        )
        return .err(.protocolStateMismatch("Session re-init failed: \(reinitError)"))
      }
      AppLogger.network.info(
        "Request pipeline: session re-initialized, retrying service=\(context.serviceType.rawValue, privacy: .public), connectId=\(context.connectId, privacy: .public)"
      )
      return await executeRequestWithProtocol(
        context: context,
        waitForRecovery: false,
        cancellationToken: cancellationToken,
        isReinitRetry: true
      )
    }
    return result
  }

  private func encryptRequestPayload(
    plainBuffer: Data,
    session: NativeProtocolSession
  ) -> Result<Data, NetworkFailure> {
    do {
      let envelopeId = UInt32.random(in: 1...UInt32.max)
      let encryptedEnvelope = try session.encrypt(
        plaintext: plainBuffer,
        envelopeType: .request,
        envelopeId: envelopeId
      )
      AppLogger.security.debug(
        "Encrypt payload: success envelopeId=\(envelopeId, privacy: .public), plainBytes=\(plainBuffer.count, privacy: .public), encryptedBytes=\(encryptedEnvelope.count, privacy: .public)"
      )
      return .ok(encryptedEnvelope)
    } catch let error as ProtocolError {
      AppLogger.security.warning(
        "Encrypt payload: protocol error \(error.message, privacy: .public)")
      return .err(
        .protocolStateMismatch(
          "\(AppConstants.Network.Request.failedEncryptPayloadPrefix) \(error.message)"))
    } catch {
      AppLogger.security.error(
        "Encrypt payload: unexpected error \(error.localizedDescription, privacy: .public)")
      return .err(.connectionFailed("Failed to encrypt request payload", innerError: error))
    }
  }

  private func buildRequestEnvelopePayload(
    context: ServiceRequestContext
  ) async -> Result<Data, NetworkFailure> {
    let envelopeResult = await rpcServiceManager.requestEnvelope(
      serviceType: context.serviceType,
      rawPayload: context.plainBuffer,
      connectId: context.connectId,
      exchangeType: context.exchangeType
    )
    guard let envelope = envelopeResult.ok() else {
      return .err(.invalidRequestType(envelopeResult.unwrapErr().logDescription))
    }
    do {
      return .ok(try envelope.serializedData())
    } catch {
      return .err(
        .invalidRequestType(
          "Failed to serialize secure request envelope: \(error.localizedDescription)"))
    }
  }

  private func decryptResponsePayload(
    encryptedPayload: Data,
    session: NativeProtocolSession
  ) -> Result<Data, NetworkFailure> {
    do {
      try NativeProtocolSession.validateEnvelope(encryptedPayload)
      let decrypted = try session.decrypt(encryptedPayload)
      AppLogger.security.debug(
        "Decrypt payload: success encryptedBytes=\(encryptedPayload.count, privacy: .public), plainBytes=\(decrypted.plaintext.count, privacy: .public)"
      )
      return .ok(decrypted.plaintext)
    } catch let error as ProtocolError {
      if error.message.lowercased().contains(AppConstants.Network.Decrypt.emptyPlaintextSignal) {
        AppLogger.security.debug(
          "Decrypt payload: empty plaintext treated as terminal signal encryptedBytes=\(encryptedPayload.count, privacy: .public)"
        )
        return .ok(Data())
      }
      AppLogger.security.warning(
        "Decrypt payload: protocol error \(error.message, privacy: .public)")
      return .err(
        .protocolStateMismatch(
          "\(AppConstants.Network.Request.failedDecryptPayloadPrefix) \(error.message)"))
    } catch {
      AppLogger.security.error(
        "Decrypt payload: unexpected error \(error.localizedDescription, privacy: .public)")
      return .err(
        .connectionFailed(
          AppConstants.Network.Request.failedDecryptResponsePayload, innerError: error))
    }
  }

  private func executeUnaryRpc(
    connectId: UInt32,
    serviceType: RpcServiceType,
    encryptedPayload: Data,
    onCompleted: @escaping (Data) async -> Result<Unit, NetworkFailure>,
    session: NativeProtocolSession,
    cancellationToken: CancellationToken
  ) async -> Result<Unit, NetworkFailure> {
    guard !cancellationToken.cancelled else {
      return .err(.operationCancelled("Cancelled before unary RPC"))
    }
    AppLogger.network.debug(
      "Unary RPC: start service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), encryptedBytes=\(encryptedPayload.count, privacy: .public)"
    )
    guard let secureEnvelope = try? ProtoSecureEnvelope(serializedBytes: encryptedPayload) else {
      return .err(
        .invalidRequestType(AppConstants.Network.Request.failedBuildSecureRequestEnvelope))
    }

    let transportResult = await rpcServiceManager.unary(
      serviceType: serviceType,
      payload: secureEnvelope,
      connectId: connectId
    )
    guard let responseEnvelope = transportResult.ok() else {
      let rpcError = transportResult.unwrapErr()
      AppLogger.network.warning(
        "Unary RPC: transport failed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(rpcError.logDescription, privacy: .public)"
      )
      return .err(mapTransportError(rpcError))
    }
    guard let secureResponse = try? ProtoSecureEnvelope(serializedBytes: responseEnvelope.payload),
      let secureResponseData = try? secureResponse.serializedData()
    else {
      return .err(
        .invalidRequestType(AppConstants.Network.Request.failedParseSecureResponseEnvelope))
    }

    let decryptedResult = decryptResponsePayload(
      encryptedPayload: secureResponseData,
      session: session
    )
    guard let decrypted = decryptedResult.ok() else {
      AppLogger.network.warning(
        "Unary RPC: decrypt failed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(decryptedResult.err()?.message ?? "", privacy: .public)"
      )
      return decryptedResult.propagateErr()
    }
    AppLogger.network.debug(
      "Unary RPC: completed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), responseBytes=\(decrypted.count, privacy: .public)"
    )
    let innerResponseEnvelope: EventEnvelope
    do {
      innerResponseEnvelope = try EventEnvelope(serializedBytes: decrypted)
    } catch {
      return .err(
        .invalidRequestType(
          "Failed to decode secure response envelope: \(error.localizedDescription)"))
    }
    if let rpcError = GatewayTransportFactory.mapOutcome(innerResponseEnvelope.metadata) {
      AppLogger.network.warning(
        "Unary RPC: server outcome error service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), outcome=\(rpcError.logDescription, privacy: .public)"
      )
      return .err(mapTransportError(rpcError))
    }
    return await onCompleted(innerResponseEnvelope.payload)
  }

  private func executeStreamingRpc(
    connectId: UInt32,
    serviceType: RpcServiceType,
    encryptedPayload: Data,
    onStreamItem: @escaping (Data) async -> Result<Unit, NetworkFailure>,
    session: NativeProtocolSession,
    cancellationToken: CancellationToken,
    exchangeType: PubKeyExchangeType
  ) async -> Result<Unit, NetworkFailure> {
    guard !cancellationToken.cancelled else {
      return .err(.operationCancelled("Cancelled before streaming RPC"))
    }
    AppLogger.network.debug(
      "Stream RPC: start service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), encryptedBytes=\(encryptedPayload.count, privacy: .public), exchange=\(String(describing: exchangeType), privacy: .public)"
    )
    guard let secureEnvelope = try? ProtoSecureEnvelope(serializedBytes: encryptedPayload) else {
      return .err(
        .invalidRequestType(AppConstants.Network.Request.failedBuildSecureStreamingRequestEnvelope))
    }

    let streamLock = NSLock()
    var streamCallbackError: NetworkFailure?
    let streamResult = await rpcServiceManager.serverStream(
      serviceType: serviceType,
      payload: secureEnvelope,
      connectId: connectId,
      exchangeType: exchangeType
    ) { responseEnvelope in
      if responseEnvelope.payload.isEmpty {
        AppLogger.network.debug(
          "Stream RPC: metadata-only item service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public)"
        )
        return
      }
      guard
        let secureResponse = try? ProtoSecureEnvelope(serializedBytes: responseEnvelope.payload),
        let secureResponseData = try? secureResponse.serializedData()
      else {
        streamLock.withLock {
          if streamCallbackError == nil {
            streamCallbackError = .invalidRequestType(
              AppConstants.Network.Request.failedParseSecureStreamEnvelope)
          }
        }
        return
      }

      let decryptedResult = self.decryptResponsePayload(
        encryptedPayload: secureResponseData,
        session: session
      )
      guard let decrypted = decryptedResult.ok() else {
        if let decryptError = decryptedResult.err() {
          streamLock.withLock {
            if streamCallbackError == nil {
              streamCallbackError = decryptError
            }
          }
        }
        return
      }
      if decrypted.isEmpty {
        AppLogger.network.debug(
          "Stream RPC: empty plaintext item service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public)"
        )
        return
      }

      let innerResponseEnvelope: EventEnvelope
      do {
        innerResponseEnvelope = try EventEnvelope(serializedBytes: decrypted)
      } catch {
        streamLock.withLock {
          if streamCallbackError == nil {
            streamCallbackError = .invalidRequestType(
              "Failed to decode secure stream envelope: \(error.localizedDescription)")
          }
        }
        return
      }
      if let rpcError = GatewayTransportFactory.mapOutcome(innerResponseEnvelope.metadata) {
        streamLock.withLock {
          if streamCallbackError == nil {
            streamCallbackError = self.mapTransportError(rpcError)
          }
        }
        return
      }

      let callbackResult = await onStreamItem(innerResponseEnvelope.payload)
      if let callbackError = callbackResult.err() {
        streamLock.withLock {
          if streamCallbackError == nil {
            streamCallbackError = callbackError
          }
        }
      }
    }
    if let failure = streamCallbackError {
      AppLogger.network.warning(
        "Stream RPC: callback/decrypt failed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(failure.message, privacy: .public)"
      )
      return .err(failure)
    }
    guard streamResult.isOk else {
      let streamError = streamResult.unwrapErr()
      AppLogger.network.warning(
        "Stream RPC: transport failed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(streamError.logDescription, privacy: .public)"
      )
      return .err(mapTransportError(streamError))
    }
    AppLogger.network.debug(
      "Stream RPC: completed service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public)"
    )
    return .ok(.value)
  }

  private func mapTransportError(_ error: RpcError) -> NetworkFailure {
    let desc = error.logDescription
    switch error {
    case .grpcError(let code, let message):
      let lower = code.lowercased()
      let normalizedMessage = message.lowercased()
      if lower == AppConstants.Network.GrpcError.unauthenticated
        && normalizedMessage.contains(ServerErrorCode.Session.reinitRequired)
      {
        return NetworkFailure(
          failureType: .protocolStateMismatch,
          message: desc,
          requiresReinit: true
        )
      }
      switch lower {
      case AppConstants.Network.GrpcError.unavailable,
        AppConstants.Network.GrpcError.deadlineExceeded,
        AppConstants.Network.GrpcError.deadlineExceededUnderscore:
        return .dataCenterNotResponding(desc)
      case AppConstants.Network.GrpcError.cancelled:
        return .operationCancelled(desc)
      case AppConstants.Network.GrpcError.unauthenticated:
        return .sessionExpired(desc)
      case AppConstants.Network.GrpcError.notFound,
        AppConstants.Network.GrpcError.notFoundUnderscore,
        AppConstants.Network.GrpcError.resourceExhausted,
        AppConstants.Network.GrpcError.resourceExhaustedUnderscore,
        AppConstants.Network.GrpcError.internal:
        return .connectionFailed(desc)
      case AppConstants.Network.GrpcError.failedPrecondition,
        AppConstants.Network.GrpcError.failedPreconditionUnderscore:
        return .protocolStateMismatch(desc)
      default:
        return .connectionFailed(desc)
      }
    case .serverError(let code, _):
      switch code {
      case ServerErrorCode.Session.reinitRequired:
        return NetworkFailure(
          failureType: .protocolStateMismatch,
          message: desc,
          requiresReinit: true
        )
      case ServerErrorCode.Session.keyUnavailable:
        return .sessionExpired(desc)
      case ServerErrorCode.Auth.signinRateLimited,
        ServerErrorCode.Auth.recoveryRateLimited,
        ServerErrorCode.RateLimit.mobileFlowExceeded,
        ServerErrorCode.RateLimit.deviceFlowExceeded,
        ServerErrorCode.RateLimit.otpSendsPerFlowExceeded,
        ServerErrorCode.RateLimit.otpSendsPerMobileExceeded:
        return .rateLimited(desc)
      case ServerErrorCode.Auth.accountLocked,
        ServerErrorCode.Auth.accountLockedEscalated:
        return .criticalAuthenticationFailure(desc)
      case ServerErrorCode.Streaming.unavailable,
        ServerErrorCode.Messaging.chatUnavailable:
        return .dataCenterNotResponding(desc)
      default:
        return .connectionFailed(desc)
      }
    case .sessionNotFound, .sessionRecoveryFailed, .encryptionFailed, .decryptionFailed:
      return .protocolStateMismatch(desc)
    case .serializationFailed, .deserializationFailed:
      return .invalidRequestType(desc)
    case .unexpected(let message):
      let normalized = message.lowercased()
      if normalized.contains(AppConstants.Network.GrpcError.unavailable)
        || normalized.contains(AppConstants.Network.GrpcError.deadline)
        || normalized.contains(AppConstants.Network.GrpcError.timeout)
        || normalized.contains(AppConstants.Network.GrpcError.timedOut)
      {
        return .dataCenterNotResponding(desc)
      }
      return .connectionFailed(desc)
    }
  }

  private func generateRequestKey(
    connectId: UInt32,
    serviceType: RpcServiceType,
    plainBuffer: Data
  ) -> String {
    "\(connectId)_\(serviceType)_\(AppConstants.Network.Request.authOperationSuffix)"
  }

  private func canServiceTypeBeDuplicated(_ serviceType: RpcServiceType) -> Bool {
    false
  }

  private func tryRegisterRequest(
    key: String,
    allowDuplicates: Bool,
    cancellationToken: CancellationToken
  ) -> Result<Unit, NetworkFailure>? {
    if !allowDuplicates && requestRegistry.contains(key) {
      return .err(.invalidRequestType(AppConstants.Network.Request.duplicateRequestInProgress))
    }

    let registryToken =
      cancellationToken === CancellationToken.none
      ? CancellationToken()
      : cancellationToken
    requestRegistry.register(key, token: registryToken)
    return nil
  }

  private func unregisterRequest(key: String) {
    requestRegistry.unregister(key)
  }

  private func waitForOutageRecovery() async {
    let maxWait = AppConstants.Network.outageRecoveryMaxWaitSeconds
    let pollInterval = AppConstants.Network.outageRecoveryPollIntervalSeconds
    let startTime = Date()
    AppLogger.network.info("\(AppConstants.Network.OutageRecovery.waitStarted, privacy: .public)")
    while outageState.currentOutageState() {
      await retryPendingRequests()
      if !outageState.currentOutageState() {
        break
      }
      if Date().timeIntervalSince(startTime) >= maxWait {
        AppLogger.network.warning(
          "\(AppConstants.Network.OutageRecovery.timeoutReachedPrefix) \(maxWait, privacy: .public)s"
        )
        break
      }
      do {
        try await Task.sleep(
          nanoseconds: UInt64(pollInterval * Double(AppConstants.Network.nanosecondsPerSecond)))
      } catch {
        AppLogger.network.debug(
          "\(AppConstants.Network.OutageRecovery.waitCancelled, privacy: .public)")
        return
      }
    }

    let outageActive = outageState.currentOutageState()
    AppLogger.network.info(
      "\(AppConstants.Network.OutageRecovery.waitFinishedPrefix)\(outageActive, privacy: .public)")
  }
}

struct ServiceRequestParams {

  let connectId: UInt32
  let serviceType: RpcServiceType
  let plainBuffer: Data
  let flowType: ServiceFlowType
  let onCompleted: (Data) async -> Result<Unit, NetworkFailure>
  let requestContext: RpcRequestContext?
  let allowDuplicateRequests: Bool
  let waitForRecovery: Bool
  let cancellationToken: CancellationToken
  let exchangeType: PubKeyExchangeType
}

struct ServiceRequestContext {

  let connectId: UInt32
  let serviceType: RpcServiceType
  let plainBuffer: Data
  let flowType: ServiceFlowType
  let onCompleted: (Data) async -> Result<Unit, NetworkFailure>
  let requestContext: RpcRequestContext?
  let exchangeType: PubKeyExchangeType
}

enum ServiceFlowType {
  case single
  case receiveStream
}
