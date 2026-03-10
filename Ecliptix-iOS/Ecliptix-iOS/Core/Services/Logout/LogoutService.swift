// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class LogoutService {

  private let authService: AuthenticationRpcService
  private let identityService: IdentityService
  private let secureStorage: SecureStorageService
  private let stateManager: ApplicationStateManager
  private let proofHandler: LogoutProofHandler
  private let pendingStorage: PendingLogoutStorage
  private let secureSessionClient: any SecureSessionClient
  private let pendingProcessor: PendingLogoutProcessor
  private let pendingLogoutTransportProvider: any PendingLogoutTransportProviding

  init(
    authService: AuthenticationRpcService,
    identityService: IdentityService,
    secureStorage: SecureStorageService,
    stateManager: ApplicationStateManager,
    proofHandler: LogoutProofHandler,
    pendingStorage: PendingLogoutStorage,
    secureSessionClient: any SecureSessionClient,
    pendingProcessor: PendingLogoutProcessor,
    pendingLogoutTransportProvider: any PendingLogoutTransportProviding
  ) {
    self.authService = authService
    self.identityService = identityService
    self.secureStorage = secureStorage
    self.stateManager = stateManager
    self.proofHandler = proofHandler
    self.pendingStorage = pendingStorage
    self.secureSessionClient = secureSessionClient
    self.pendingProcessor = pendingProcessor
    self.pendingLogoutTransportProvider = pendingLogoutTransportProvider
    #if DEBUG
      _ = LogoutKeyDerivation._selfTest
    #endif
  }

  func logoutAsync(reason: LogoutReason) async -> Result<Unit, LogoutFailure> {
    let membershipResult = validateAndGetMembership()
    guard let membershipId = membershipResult.ok() else {
      return membershipResult.propagateErr()
    }

    let accountResult = validateAndGetAccount()
    guard let accountId = accountResult.ok() else {
      return accountResult.propagateErr()
    }

    let prepareResult = await prepareLogoutRequest(
      membershipId: membershipId,
      accountId: accountId,
      reason: reason
    )
    guard let (request, connectId) = prepareResult.ok() else {
      return prepareResult.propagateErr()
    }

    let serverResult = await executeServerLogout(request: request, connectId: connectId)
    if serverResult.isErr {
      return await handleFailedLogout(
        request: request,
        membershipId: membershipId,
        accountId: accountId,
        reason: reason,
        connectId: connectId
      )
    }
    guard let response = serverResult.ok() else {
      return .err(.unexpectedError("Logout response unavailable"))
    }
    return await processSuccessfulLogout(
      response: response,
      membershipId: membershipId,
      accountId: accountId,
      reason: reason,
      connectId: connectId
    )
  }

  private func validateAndGetMembership() -> Result<UUID, LogoutFailure> {
    guard let settings = secureStorage.settings,
      let membership = settings.membership
    else {
      return .err(.invalidMembershipIdentifier(AppConstants.Logout.noActiveSessionFound))
    }
    return .ok(membership.membershipId)
  }

  private func validateAndGetAccount() -> Result<UUID, LogoutFailure> {
    guard let settings = secureStorage.settings,
      let accountId = settings.currentAccountId
    else {
      return .err(.invalidMembershipIdentifier(AppConstants.Logout.noActiveAccountFound))
    }
    return .ok(accountId)
  }

  private func prepareLogoutRequest(
    membershipId: UUID,
    accountId: UUID,
    reason: LogoutReason
  ) async -> Result<(AuthenticatedLogoutRequest, UInt32), LogoutFailure> {
    guard let settings = secureStorage.settings else {
      return .err(.networkRequestFailed(AppConstants.Logout.failedToGetApplicationSettings))
    }

    var request = AuthenticatedLogoutRequest()
    request.membershipID = membershipId.protobufBytes
    request.logoutReason = reason
    request.accountID = accountId.protobufBytes
    var timestamp = Google_Protobuf_Timestamp()
    let now = Date().timeIntervalSince1970
    timestamp.seconds = Int64(now)
    timestamp.nanos = Int32((now - floor(now)) * 1_000_000_000)
    request.timestamp = timestamp
    request.scope = .thisDevice
    let hmacResult = await proofHandler.generateLogoutHmacProof(
      request: request,
      accountId: accountId
    )
    guard let hmacProof = hmacResult.ok() else {
      return hmacResult.propagateErr()
    }
    request.hmacProof = hmacProof
    let connectId = NetworkProvider.computeUniqueConnectId(
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId,
      exchangeType: .dataCenterEphemeralConnect
    )
    return .ok((request, connectId))
  }

  private func executeServerLogout(
    request: AuthenticatedLogoutRequest,
    connectId: UInt32
  ) async -> Result<AuthenticatedLogoutResponse, LogoutFailure> {
    let result = await authService.terminateSession(
      request: request,
      connectId: connectId
    )
    guard let response = result.ok() else {
      return .err(.networkRequestFailed(result.unwrapErr().logDescription))
    }
    return mapLogoutResponse(response)
  }

  private func mapLogoutResponse(_ response: AuthenticatedLogoutResponse) -> Result<
    AuthenticatedLogoutResponse, LogoutFailure
  > {
    switch response.result {
    case .succeeded:
      return .ok(response)
    case .alreadyLoggedOut:
      return .err(.alreadyLoggedOut(AppConstants.Logout.sessionAlreadyLoggedOutOnServer))
    case .sessionNotFound:
      return .err(.sessionNotFound(AppConstants.Logout.activeSessionNotFoundOnServer))
    case .invalidTimestamp:
      return .err(.unexpectedError(AppConstants.Logout.serverRejectedLogoutTimestampMismatch))
    case .invalidHmac:
      return .err(
        .cryptographicOperationFailed(AppConstants.Logout.serverRejectedLogoutInvalidHmac))
    case .failed:
      return .err(.unexpectedError(AppConstants.Logout.serverFailedToCompleteLogout))
    default:
      return .err(.unexpectedError(AppConstants.Logout.serverReturnedUnknownLogoutStatus))
    }
  }

  private func processSuccessfulLogout(
    response: AuthenticatedLogoutResponse,
    membershipId: UUID,
    accountId: UUID,
    reason: LogoutReason,
    connectId: UInt32
  ) async -> Result<Unit, LogoutFailure> {
    AppLogger.auth.info(
      "[LOGOUT] Server logout succeeded for membershipId=\(membershipId.uuidString, privacy: .public)"
    )
    let verifyResult = await proofHandler.verifyRevocationProof(
      proofData: response.revocationProof,
      membershipId: membershipId,
      accountId: accountId,
      connectId: connectId,
      serverTimestamp: response.serverTimestamp.seconds
    )
    if let failure = verifyResult.err() {
      AppLogger.auth.warning(
        "[LOGOUT] Revocation proof verification failed: \(failure.message, privacy: .public)")
    }
    await completeLogoutWithCleanup(
      membershipId: membershipId,
      accountId: accountId,
      reason: reason,
      connectId: connectId,
      keepPendingLogout: false
    )
    return .ok(.value)
  }

  private func handleFailedLogout(
    request: AuthenticatedLogoutRequest,
    membershipId: UUID,
    accountId: UUID,
    reason: LogoutReason,
    connectId: UInt32
  ) async -> Result<Unit, LogoutFailure> {
    AppLogger.auth.warning(
      "[LOGOUT] Server logout failed, storing pending and proceeding with local cleanup")
    if let requestData = serializePendingLogoutRequest(from: request) {
      pendingStorage.storePendingLogout(
        requestData,
        networkConfiguration: currentPendingLogoutNetworkConfiguration()
      )
    } else {
      AppLogger.auth.warning("[LOGOUT] Failed to serialize pending logout request")
    }
    await completeLogoutWithCleanup(
      membershipId: membershipId,
      accountId: accountId,
      reason: reason,
      connectId: connectId,
      keepPendingLogout: true
    )
    return .ok(.value)
  }

  private func serializePendingLogoutRequest(from request: AuthenticatedLogoutRequest) -> Data? {
    var pendingRequest = LogoutRequest()
    pendingRequest.membershipID = request.membershipID
    pendingRequest.logoutReason = request.logoutReason
    pendingRequest.timestamp = request.timestamp
    pendingRequest.hmacProof = request.hmacProof
    pendingRequest.scope = request.scope
    if request.hasAccountID {
      pendingRequest.accountID = request.accountID
    }
    return try? pendingRequest.serializedData()
  }

  private func currentPendingLogoutNetworkConfiguration() -> NetworkConfiguration? {
    do {
      return try pendingLogoutTransportProvider.getNetworkConfiguration()
    } catch {
      AppLogger.auth.warning(
        "[LOGOUT] Unable to capture network configuration for pending logout retry: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private func completeLogoutWithCleanup(
    membershipId: UUID,
    accountId: UUID,
    reason: LogoutReason,
    connectId: UInt32,
    keepPendingLogout: Bool
  ) async {
    let cleanupResult = await identityService.cleanupMembershipStateWithKeys(
      accountId: accountId,
      connectId: connectId
    )
    if cleanupResult.isErr {
      AppLogger.auth.warning(
        "Logout cleanup: failed for accountId=\(accountId.uuidString, privacy: .public), error=\(cleanupResult.err() ?? "Unknown error", privacy: .public)"
      )
    }
    _ = await secureStorage.setMembership(nil)
    _ = await secureStorage.setCurrentAccountId(nil)
    secureStorage.clearCaches()
    secureSessionClient.clearConnection(connectId: connectId)
    await proofHandler.clearRevocationProof(membershipId: membershipId)
    if !keepPendingLogout {
      pendingStorage.clearPendingLogout()
    }
    await finalizeLogout(
      membershipId: membershipId,
      reason: reason,
      shouldRetryPendingLogout: keepPendingLogout
    )
  }

  private func finalizeLogout(
    membershipId: UUID,
    reason: LogoutReason,
    shouldRetryPendingLogout: Bool
  ) async {
    await stateManager.transitionToAnonymous()
    NotificationCenter.default.post(
      name: .membershipLoggedOut,
      object: nil,
      userInfo: [
        "membershipId": membershipId.uuidString,
        "reason": String(describing: reason),
      ]
    )
    if shouldRetryPendingLogout {
      guard let settings = secureStorage.settings else { return }
      let anonymousConnectId = NetworkProvider.computeUniqueConnectId(
        deviceId: settings.deviceId,
        appInstanceId: settings.appInstanceId,
        exchangeType: .dataCenterEphemeralConnect
      )
      Task(priority: .utility) { [pendingProcessor] in
        await pendingProcessor.processPendingLogout(connectId: anonymousConnectId)
      }
    }
  }
}

extension Notification.Name {

  static let membershipLoggedOut = Notification.Name("com.ecliptix.membershipLoggedOut")
}
