// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

final class NetworkProvider: @unchecked Sendable {

  let dependencies: NetworkProviderDependencies
  let services: NetworkProviderServices
  let security: NetworkProviderSecurity
  let rpcServiceManager: RpcServiceManager
  let secureStorageService: SecureStorageService
  let protocolStateStorage: ProtocolStateStorage
  let runtime: NetworkProviderRuntime
  private static let defaultCultureCode = "en-US"
  private static let authenticatedEstablishClientNonceLength = 32
  private static let authenticatedEstablishProofContext = Data(
    "Ecliptix.AuthenticatedEstablish.v1".utf8)

  var nativeSessions: SecureSessionRuntime {
    runtime.sessionRuntime
  }

  init(
    dependencies: NetworkProviderDependencies,
    services: NetworkProviderServices,
    security: NetworkProviderSecurity,
    rpcServiceManager: RpcServiceManager,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    runtime: NetworkProviderRuntime
  ) {
    self.dependencies = dependencies
    self.services = services
    self.security = security
    self.rpcServiceManager = rpcServiceManager
    self.secureStorageService = secureStorageService
    self.protocolStateStorage = protocolStateStorage
    self.runtime = runtime
  }

  func hasActiveRequest(forKey key: String) -> Bool {
    runtime.requestRegistry.contains(key)
  }

  func registerActiveRequest(forKey key: String, token: CancellationToken) {
    runtime.requestRegistry.register(key, token: token)
  }

  func unregisterActiveRequest(forKey key: String) {
    runtime.requestRegistry.unregister(key)
  }

  func establishSecrecyChannel(
    request: SecrecyChannelRequest
  ) async -> Result<SessionState?, NetworkFailure> {
    await establishSecrecyChannelInternal(request: request)
  }

  func setCountry(_ country: String) {
    runtime.instanceSettingsStore.update { settings in
      settings.country = country
    }
  }

  func setCulture(_ culture: String) {
    runtime.instanceSettingsStore.update { settings in
      settings.culture = culture
    }
  }

  func getApplicationInstanceSettings() -> Result<NetworkProviderInstanceSettings, NetworkFailure> {
    guard let settings = runtime.instanceSettingsStore.current() else {
      return .err(
        .invalidRequestType(
          "ApplicationInstanceSettings has not been initialized"
        )
      )
    }
    return .ok(settings)
  }
}

extension NetworkProvider {

  private func establishSecrecyChannelInternal(
    request: SecrecyChannelRequest
  ) async -> Result<SessionState?, NetworkFailure> {
    publishConnectingEventIfNeeded(
      exchangeType: request.exchangeType,
      connectId: request.connectId
    )
    let prepareResult = await prepareHandshakePayload(request: request)
    guard case .ok(let handshakePayload) = prepareResult else {
      return prepareResult.propagateErr()
    }

    let rpcResult = await executeEstablishChannelRpcRaw(
      request: request,
      handshakePayload: handshakePayload
    )
    guard case .ok(let handshakeAckPayload) = rpcResult else {
      if case .err(let failure) = rpcResult {
        return handleEstablishChannelFailure(
          failure: failure,
          request: request
        )
      }
      return .err(.connectionFailed("Unknown establish channel failure"))
    }

    let processResult = processHandshakeRawResponse(
      handshakeAckPayload: handshakeAckPayload,
      connectId: request.connectId
    )
    guard processResult.isOk else {
      return processResult.propagateErr()
    }

    let result = await createAndPersistSessionState(
      request: request,
      handshakeInit: handshakePayload
    )
    if result.isOk {
      publishConnectedEvent(connectId: request.connectId)
    }
    return result
  }

  private func executeEstablishChannelRpcRaw(
    request: SecrecyChannelRequest,
    handshakePayload: Data
  ) async -> Result<Data, NetworkFailure> {
    let finalToken =
      request.cancellationToken.cancelled ? CancellationToken.none : request.cancellationToken
    let operationName = "EstablishSecrecyChannel"
    if let maxRetries = request.maxRetries {
      return await services.retryStrategy.executeRpcOperation(
        { attempt, token in
          await self.callEstablishSecrecyChannelRpcRaw(
            connectId: request.connectId,
            handshakePayload: handshakePayload,
            exchangeType: request.exchangeType,
            cancellationToken: token
          )
        },
        operationName: operationName,
        connectId: request.connectId,
        serviceType: .establishSecrecyChannel,
        maxRetries: maxRetries,
        cancellationToken: finalToken
      )
    }
    return await services.retryStrategy.executeRpcOperation(
      { attempt, token in
        await self.callEstablishSecrecyChannelRpcRaw(
          connectId: request.connectId,
          handshakePayload: handshakePayload,
          exchangeType: request.exchangeType,
          cancellationToken: token
        )
      },
      operationName: operationName,
      connectId: request.connectId,
      serviceType: .establishSecrecyChannel,
      maxRetries: nil,
      cancellationToken: finalToken
    )
  }

  private func callEstablishSecrecyChannelRpcRaw(
    connectId: UInt32,
    handshakePayload: Data,
    exchangeType: PubKeyExchangeType,
    cancellationToken: CancellationToken
  ) async -> Result<Data, NetworkFailure> {
    _ = cancellationToken
    let result = await sendEstablishChannelRpcRaw(
      connectId: connectId,
      handshakePayload: handshakePayload,
      exchangeType: exchangeType
    )
    guard let response = result.ok() else {
      let rpcError = result.unwrapErr()
      if rpcError.isTransient {
        return .err(.dataCenterNotResponding(rpcError.logDescription))
      }
      return .err(.connectionFailed(rpcError.logDescription))
    }
    return .ok(response)
  }

  private func handleEstablishChannelFailure(
    failure: NetworkFailure,
    request: SecrecyChannelRequest
  ) -> Result<SessionState?, NetworkFailure> {
    cleanupFailedAuthentication(connectId: request.connectId)
    if request.enablePendingRegistration && shouldQueueSecrecyChannelRetry(failure: failure) {
      queueSecrecyChannelEstablishRetry(
        connectId: request.connectId,
        exchangeType: request.exchangeType,
        maxRetries: request.maxRetries,
        saveState: request.saveState
      )
    }
    return .err(failure)
  }

  private func createAndPersistSessionState(
    request: SecrecyChannelRequest,
    handshakeInit: Data
  ) async -> Result<SessionState?, NetworkFailure> {
    guard shouldPersistSessionState(request: request) else {
      return .ok(nil)
    }

    let stateResult = await createSessionState(
      connectId: request.connectId,
      handshakeInit: handshakeInit,
      exchangeType: request.exchangeType,
      membershipId: Data(),
      accountId: Data(),
      identitySeed: nil
    )
    guard case .ok(let state) = stateResult else {
      return stateResult.propagateErr()
    }
    if request.enablePendingRegistration {
      let key = buildSecrecyChannelPendingKey(
        connectId: request.connectId,
        exchangeType: request.exchangeType
      )
      services.pendingRequestManager.removePendingRequest(key)
      exitOutage()
    }
    return .ok(state)
  }

  private func createSessionState(
    connectId: UInt32,
    handshakeInit: Data,
    exchangeType: PubKeyExchangeType,
    membershipId: Data,
    accountId: Data,
    identitySeed: Data?
  ) async -> Result<SessionState, NetworkFailure> {
    let state = SessionState(
      connectId: connectId,
      exchangeType: exchangeType,
      peerHandshakeInit: handshakeInit,
      membershipId: membershipId,
      accountId: accountId,
      identitySeed: identitySeed
    )
    return .ok(state)
  }
}

extension NetworkProvider {

  private func publishConnectingEventIfNeeded(
    exchangeType: PubKeyExchangeType,
    connectId: UInt32
  ) {
    guard exchangeType == .dataCenterEphemeralConnect else {
      return
    }
    Task { @MainActor [weak self] in
      await self?.services.connectivityService.publishAsync(.connecting(connectId))
    }
  }

  private func publishConnectedEvent(connectId: UInt32) {
    Task { @MainActor [weak self] in
      await self?.services.connectivityService.publishAsync(.connected(connectId))
    }
  }

  private func shouldPersistSessionState(request: SecrecyChannelRequest) -> Bool {
    request.saveState && request.exchangeType == .dataCenterEphemeralConnect
  }

  private func shouldQueueSecrecyChannelRetry(failure: NetworkFailure) -> Bool {
    switch failure.failureType {
    case .dataCenterNotResponding, .connectionFailed:
      return true
    default:
      return false
    }
  }

  private func queueSecrecyChannelEstablishRetry(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType,
    maxRetries: Int?,
    saveState: Bool
  ) {
    let key = buildSecrecyChannelPendingKey(connectId: connectId, exchangeType: exchangeType)
    let pendingRequest = PendingRequest(
      key: key,
      connectId: connectId,
      exchangeType: exchangeType,
      maxRetries: maxRetries,
      saveState: saveState
    )
    services.pendingRequestManager.addPendingRequest(key: key, request: pendingRequest)
    AppLogger.network.warning(
      "Secrecy recovery: queued pending establish key=\(key, privacy: .public), connectId=\(connectId, privacy: .public), exchangeType=\(exchangeType.rawValue, privacy: .public)"
    )
    enterOutage()
  }

  private func buildSecrecyChannelPendingKey(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType
  ) -> String {
    "secrecy_channel:\(connectId):\(exchangeType.rawValue)"
  }

  func checkIsInOutage() -> Bool {
    runtime.outageState.currentOutageState()
  }

  func enterOutage() {
    runtime.outageState.enterOutage()
    AppLogger.network.warning("Secrecy recovery: entered outage mode")
  }

  func exitOutage() {
    runtime.outageState.exitOutage()
    AppLogger.network.info("Secrecy recovery: exited outage mode")
  }

  func clearExhaustedOperations() {
    let pending = services.pendingRequestManager.listPendingRequests()
    for request in pending {
      if let maxRetries = request.maxRetries, maxRetries <= 0 {
        services.pendingRequestManager.removePendingRequest(request.key)
        AppLogger.network.info(
          "Cleared exhausted pending request key=\(request.key, privacy: .public)"
        )
      }
    }
  }

  func retryPendingSecrecyChannelRequests() async {
    let shouldProceed = runtime.outageState.beginPendingRetry()
    guard shouldProceed else {
      return
    }
    defer {
      runtime.outageState.finishPendingRetry()
    }

    let pendingRequests = services.pendingRequestManager.listPendingRequests()
    guard !pendingRequests.isEmpty else {
      return
    }
    AppLogger.network.info(
      "Secrecy recovery: retrying pending requests count=\(pendingRequests.count, privacy: .public)"
    )
    var restoredAtLeastOne = false
    for pending in pendingRequests {
      AppLogger.network.debug(
        "Secrecy recovery: retry pending key=\(pending.key, privacy: .public), connectId=\(pending.connectId, privacy: .public)"
      )
      let result = await establishSecrecyChannel(
        request: SecrecyChannelRequest(
          connectId: pending.connectId,
          exchangeType: pending.exchangeType,
          maxRetries: pending.maxRetries,
          saveState: pending.saveState,
          enablePendingRegistration: false
        )
      )
      if result.isOk {
        services.pendingRequestManager.removePendingRequest(pending.key)
        restoredAtLeastOne = true
        AppLogger.network.info(
          "Secrecy recovery: pending restored key=\(pending.key, privacy: .public), connectId=\(pending.connectId, privacy: .public)"
        )
      } else if let error = result.err() {
        AppLogger.network.warning(
          "Secrecy recovery: pending retry failed key=\(pending.key, privacy: .public), connectId=\(pending.connectId, privacy: .public), error=\(error.message, privacy: .public)"
        )
      }
    }
    if restoredAtLeastOne {
      exitOutage()
    }
  }
}

struct SecrecyChannelRequest {

  let connectId: UInt32
  let exchangeType: PubKeyExchangeType
  let maxRetries: Int?
  let saveState: Bool
  let enablePendingRegistration: Bool
  let cancellationToken: CancellationToken

  init(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType,
    maxRetries: Int? = nil,
    saveState: Bool = true,
    enablePendingRegistration: Bool = true,
    cancellationToken: CancellationToken = .none
  ) {
    self.connectId = connectId
    self.exchangeType = exchangeType
    self.maxRetries = maxRetries
    self.saveState = saveState
    self.enablePendingRegistration = enablePendingRegistration
    self.cancellationToken = cancellationToken
  }
}

struct NetworkProviderInstanceSettings {

  var deviceId: UUID
  var appInstanceId: UUID
  var platform: String
  var country: String
  var culture: String
  var appVersion: String
  var osVersion: String

  init(
    deviceId: UUID,
    appInstanceId: UUID,
    platform: String = "iOS",
    country: String = "US",
    culture: String = Locale.current.identifier,
    appVersion: String = "1.0.0",
    osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
  ) {
    self.deviceId = deviceId
    self.appInstanceId = appInstanceId
    self.platform = platform
    self.country = country
    self.culture = culture
    self.appVersion = appVersion
    self.osVersion = osVersion
  }
}

struct SecureEnvelope {

  let payload: Data
  let signature: Data?
  let metadata: [String: String]

  init(payload: Data, signature: Data? = nil, metadata: [String: String] = [:]) {
    self.payload = payload
    self.signature = signature
    self.metadata = metadata
  }
}
