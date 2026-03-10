// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os.log

final class SecureKeyRecoveryService: @unchecked Sendable {

  private let secureSessionClient: any SecureSessionClient
  private let authenticationRpcService: AuthenticationRpcService
  private let secureStorageService: SecureStorageService
  private let agentCache = OpaqueAgentCache()
  private let stateManager = RegistrationStateManager()

  init(
    secureSessionClient: any SecureSessionClient,
    authenticationRpcService: AuthenticationRpcService,
    secureStorageService: SecureStorageService
  ) {
    self.secureSessionClient = secureSessionClient
    self.authenticationRpcService = authenticationRpcService
    self.secureStorageService = secureStorageService
  }

  func completeSecureKeyRecovery(
    membershipIdBytes: Data,
    secureKey: SecureTextBuffer
  ) async -> Result<Unit, String> {
    AppLogger.auth.info("SecureKeyRecovery: start")
    guard let lockGeneration = stateManager.tryAcquire(membershipIdBytes) else {
      AppLogger.auth.warning("SecureKeyRecovery: already in progress")
      return .err(ErrorI18NKeys.recoveryInProgress)
    }
    defer { stateManager.release(membershipIdBytes, generation: lockGeneration) }

    let settings = secureStorageService.settings
    let connectDeviceId = settings?.deviceId ?? NetworkConfiguration.default.deviceId
    let connectAppInstanceId = settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    let connectId = NetworkProvider.computeUniqueConnectId(
      deviceId: connectDeviceId,
      appInstanceId: connectAppInstanceId,
      exchangeType: .dataCenterEphemeralConnect
    )
    let serverPublicKeyResult = await secureSessionClient.getServerPublicKey(connectId: connectId)
    guard let serverPublicKey = serverPublicKeyResult.ok() else {
      let errorMessage = serverPublicKeyResult.err()?.message ?? "Unknown error"
      AppLogger.auth.error(
        "SecureKeyRecovery: server public key failed, error=\(errorMessage, privacy: .public)")
      return .err(
        "\(AppConstants.OpaqueRegistration.failedToGetServerPublicKeyPrefix) \(errorMessage)")
    }
    guard !membershipIdBytes.isEmpty else {
      AppLogger.auth.error("SecureKeyRecovery: empty membershipIdBytes")
      return .err(ErrorI18NKeys.membershipIdRequired)
    }
    guard secureKey.length > 0 else {
      AppLogger.auth.warning("SecureKeyRecovery: empty secure key")
      return .err(ErrorI18NKeys.secureKeyRequired)
    }
    return await TransientErrorDetection.executeWithRetry { [self] in
      guard var secureKeyBytes = secureKey.withSecureBytes({ Data($0) }), !secureKeyBytes.isEmpty
      else {
        AppLogger.auth.warning("SecureKeyRecovery: secure key unavailable during retry")
        return .err(ErrorI18NKeys.secureKeyRequired)
      }
      defer { OpaqueNative.secureZeroData(&secureKeyBytes) }

      return await executeRecoveryOpaqueFlow(
        membershipIdBytes: membershipIdBytes,
        secureKeyBytes: secureKeyBytes,
        serverPublicKey: serverPublicKey,
        connectId: connectId
      )
    }
  }

  private func executeRecoveryOpaqueFlow(
    membershipIdBytes: Data,
    secureKeyBytes: Data,
    serverPublicKey: Data,
    connectId: UInt32
  ) async -> Result<Unit, String> {
    AppLogger.auth.debug("RecoveryOPAQUE: flow start connectId=\(connectId, privacy: .public)")
    do {
      let opaqueAgent = try agentCache.getOrCreateAgent(serverPublicKey: serverPublicKey)
      let registrationState = try opaqueAgent.createRegistrationRequest(secureKeyBytes)
      defer { registrationState.dispose() }

      guard var requestData = registrationState.getRequestCopy() else {
        AppLogger.auth.error("RecoveryOPAQUE: recovery request data unavailable")
        return .err(ErrorI18NKeys.recoveryRequestUnavailable)
      }
      defer { OpaqueNative.secureZeroData(&requestData) }

      var initRequest = OpaqueRecoveryInitRequest()
      initRequest.peerOprf = requestData
      initRequest.membershipID = membershipIdBytes
      let initResult = await authenticationRpcService.recoveryOpaqueInit(
        request: initRequest,
        connectId: connectId
      )
      guard let initResponse = initResult.ok() else {
        let rpcError = initResult.unwrapErr()
        AppLogger.auth.error(
          "RecoveryOPAQUE: init RPC failed, error=\(rpcError.logDescription, privacy: .public)")
        return .err(rpcError.logDescription)
      }
      guard initResponse.result.rawValue == AppConstants.Opaque.resultSucceeded else {
        let message =
          initResponse.message.isEmpty
          ? ErrorI18NKeys.recoveryInitFailed
          : initResponse.message
        AppLogger.auth.warning(
          "RecoveryOPAQUE: init server rejected result=\(initResponse.result.rawValue, privacy: .public), message=\(message, privacy: .public)"
        )
        return .err(message)
      }
      AppLogger.auth.debug("RecoveryOPAQUE: init succeeded, finalizing recovery record")
      var recoveryRecord = try opaqueAgent.finalizeRegistration(
        initResponse.peerOprf,
        registrationState
      )
      defer { OpaqueNative.secureZeroData(&recoveryRecord) }

      var completeRequest = OpaqueRecoveryCompleteRequest()
      completeRequest.peerRecoveryRecord = recoveryRecord
      completeRequest.membershipID = membershipIdBytes
      let completeResult = await authenticationRpcService.recoveryOpaqueComplete(
        request: completeRequest,
        connectId: connectId
      )
      guard let completeResponse = completeResult.ok() else {
        let rpcError = completeResult.unwrapErr()
        AppLogger.auth.error(
          "RecoveryOPAQUE: complete RPC failed, error=\(rpcError.logDescription, privacy: .public)")
        return .err(rpcError.logDescription)
      }
      if completeResponse.hasMessage, !completeResponse.message.isEmpty {
        AppLogger.auth.info(
          "RecoveryOPAQUE: server message=\(completeResponse.message, privacy: .public)")
      }
      AppLogger.auth.info(
        "RecoveryOPAQUE: complete success connectId=\(connectId, privacy: .public)")
      return .ok(.value)
    } catch let error as OpaqueError {
      AppLogger.auth.error("RecoveryOPAQUE: OPAQUE error=\(error.message, privacy: .public)")
      return .err(error.message)
    } catch {
      AppLogger.auth.error(
        "RecoveryOPAQUE: unexpected error=\(error.localizedDescription, privacy: .public)")
      return .err(error.localizedDescription)
    }
  }
}
