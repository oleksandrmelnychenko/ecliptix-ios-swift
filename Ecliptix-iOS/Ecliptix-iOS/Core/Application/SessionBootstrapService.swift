// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

final class SessionBootstrapService {

  private let bootstrapClient: any ApplicationBootstrapClient
  private let secureStorage: SecureStorageService
  private let protocolStateStorage: ProtocolStateStorage
  private let identityService: IdentityService
  private let stateManager: any ApplicationStateTransitioning

  init(
    bootstrapClient: any ApplicationBootstrapClient,
    secureStorage: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService,
    stateManager: any ApplicationStateTransitioning
  ) {
    self.bootstrapClient = bootstrapClient
    self.secureStorage = secureStorage
    self.protocolStateStorage = protocolStateStorage
    self.identityService = identityService
    self.stateManager = stateManager
  }

  func ensureSecrecyChannel(
    settings: ApplicationInstanceSettings,
    isNewInstance: Bool
  ) async -> Result<UInt32, String> {
    let connectId: UInt32 = NetworkProvider.computeUniqueConnectId(
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId,
      exchangeType: .dataCenterEphemeralConnect
    )
    AppLogger.security.info(
      "Secrecy channel: resolved connectId=\(connectId, privacy: .public), isNewInstance=\(isNewInstance, privacy: .public)"
    )
    if !isNewInstance {
      if let restored = await tryRestoreExistingSession(
        connectId: connectId,
        settings: settings
      ) {
        return restored
      }
      AppLogger.security.info(
        "Secrecy channel: restore unavailable, switching to fresh handshake for connectId=\(connectId, privacy: .public)"
      )
    }
    return await establishNewSecrecyChannel(
      settings: settings,
      connectId: connectId
    )
  }

  private func tryRestoreExistingSession(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Result<UInt32, String>? {
    bootstrapClient.clearConnection(connectId: connectId)
    AppLogger.security.debug(
      "Restore flow: cleared active connection for connectId=\(connectId, privacy: .public)")
    let restoreResult = await tryRestoreSessionState(
      connectId: connectId,
      settings: settings
    )
    guard let restored = restoreResult.ok() else {
      let failure: String = restoreResult.err() ?? ""
      AppLogger.security.warning(
        "Restore flow: failed for connectId=\(connectId, privacy: .public), failure=\(failure, privacy: .public)"
      )
      if shouldFallbackFromRestoreFailure(failure: failure) {
        await handleRestoreFallback(
          connectId: connectId,
          settings: settings,
          failure: failure
        )
        return nil
      }
      return .err(failure)
    }
    if !restored {
      AppLogger.security.info(
        "Restore flow: no persisted state restored for connectId=\(connectId, privacy: .public)")
      return nil
    }
    AppLogger.security.info(
      "Restore flow: persisted session restored for connectId=\(connectId, privacy: .public)")
    if let membership = settings.membership,
      let accountId = settings.currentAccountId
    {
      let hasIdentity = await identityService.hasStoredIdentity(accountId: accountId)
      if hasIdentity {
        AppLogger.auth.info(
          "Restore flow: identity available, transitioning to authenticated for membershipId=\(membership.membershipId.uuidString, privacy: .public)"
        )
        await stateManager.transitionToAuthenticated(
          membershipId: membership.membershipId.uuidString
        )
      }
    }
    return .ok(connectId)
  }

  private func tryRestoreSessionState(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Result<Bool, String> {
    guard let accountId = settings.currentAccountId else {
      AppLogger.security.debug(
        "Restore state: accountId missing, skipping restore for connectId=\(connectId, privacy: .public)"
      )
      return .ok(false)
    }

    let accountIdData = accountId.protobufBytes
    let loadResult = await protocolStateStorage.loadState(
      connectId: String(connectId),
      accountId: accountIdData
    )
    guard let (sealedState, minExternalCounter) = loadResult.ok() else {
      if let loadError = loadResult.err() {
        AppLogger.security.warning(
          "Restore state: corrupted persisted state for connectId=\(connectId, privacy: .public), error=\(loadError, privacy: .public), deleting"
        )
        _ = await protocolStateStorage.deleteState(connectId: String(connectId))
      } else {
        AppLogger.security.debug(
          "Restore state: no persisted file for connectId=\(connectId, privacy: .public)")
      }
      return .ok(false)
    }
    AppLogger.security.debug(
      "Restore state: loaded persisted bytes=\(sealedState.count, privacy: .public) for connectId=\(connectId, privacy: .public)"
    )
    guard sealedState.count > 4 else {
      AppLogger.security.warning(
        "Restore state: corrupted state (too small, bytes=\(sealedState.count)), cleaning up for connectId=\(connectId, privacy: .public)"
      )
      bootstrapClient.clearConnection(connectId: connectId)
      let deleteCorruptedResult = await protocolStateStorage.deleteState(
        connectId: String(connectId))
      if deleteCorruptedResult.isErr {
        AppLogger.security.warning(
          "Restore state: failed to delete corrupted state for connectId=\(connectId, privacy: .public), error=\(deleteCorruptedResult.err() ?? "", privacy: .public)"
        )
      }
      return .ok(false)
    }
    guard settings.membership != nil else {
      AppLogger.security.debug(
        "Restore state: membership missing despite having persisted state, cleaning up for connectId=\(connectId, privacy: .public)"
      )
      bootstrapClient.clearConnection(connectId: connectId)
      let deleteOrphanedResult = await protocolStateStorage.deleteState(
        connectId: String(connectId))
      if deleteOrphanedResult.isErr {
        AppLogger.security.warning(
          "Restore state: failed to delete orphaned state for connectId=\(connectId, privacy: .public), error=\(deleteOrphanedResult.err() ?? "", privacy: .public)"
        )
      }
      return .ok(false)
    }
    if let membership = settings.membership {
      let hasRevocationProof = await hasRevocationProof(
        membershipId: membership.membershipId.uuidString
      )
      if hasRevocationProof {
        await handleRevokedSession(
          connectId: connectId,
          accountId: settings.currentAccountId,
          membershipId: membership.membershipId
        )
        return .ok(false)
      }
    }

    let sealKeyResult = await deriveSealKey(
      accountId: settings.currentAccountId,
      membershipId: settings.membership?.membershipId
    )
    guard let sealKey = sealKeyResult.ok() else {
      let failure = sealKeyResult.err() ?? "Unknown sealed-state key derivation failure"
      AppLogger.security.warning(
        "Restore state: \(failure, privacy: .public), clearing persisted state for connectId=\(connectId, privacy: .public)"
      )
      bootstrapClient.clearConnection(connectId: connectId)
      let deleteFailedResult = await protocolStateStorage.deleteState(connectId: String(connectId))
      if deleteFailedResult.isErr {
        AppLogger.security.warning(
          "Restore state: failed to delete state after seal key failure for connectId=\(connectId, privacy: .public), error=\(deleteFailedResult.err() ?? "", privacy: .public)"
        )
      }
      return .ok(false)
    }

    let restoreResult = await bootstrapClient.restoreSecrecyChannel(
      sealedState: sealedState,
      connectId: connectId,
      settings: settings,
      sealKey: sealKey,
      minExternalCounter: minExternalCounter
    )
    guard restoreResult.isOk else {
      AppLogger.security.warning(
        "Restore state: native restore failed, clearing persisted state for connectId=\(connectId, privacy: .public)"
      )
      bootstrapClient.clearConnection(connectId: connectId)
      let deleteFailedResult = await protocolStateStorage.deleteState(connectId: String(connectId))
      if deleteFailedResult.isErr {
        AppLogger.security.warning(
          "Restore state: failed to delete state after restore failure for connectId=\(connectId, privacy: .public), error=\(deleteFailedResult.err() ?? "", privacy: .public)"
        )
      }
      return .ok(false)
    }
    AppLogger.security.info(
      "Restore state: native restore succeeded for connectId=\(connectId, privacy: .public)")
    return .ok(true)
  }

  private func establishNewSecrecyChannel(
    settings: ApplicationInstanceSettings,
    connectId: UInt32
  ) async -> Result<UInt32, String> {
    AppLogger.security.info(
      "Fresh channel flow: start connectId=\(connectId, privacy: .public), hasMembership=\((settings.membership != nil), privacy: .public), hasAccount=\((settings.currentAccountId != nil), privacy: .public)"
    )
    if let masterKey = await loadMasterKey(settings: settings),
      let membership = settings.membership,
      let accountId = settings.currentAccountId
    {
      AppLogger.auth.info(
        "Fresh channel flow: keychain master key loaded for accountId=\(accountId.uuidString, privacy: .public)"
      )
      let result = await bootstrapClient.recreateProtocolWithMasterKey(
        masterKey: masterKey,
        membershipId: membership.membershipId,
        accountId: accountId,
        connectId: connectId
      )
      if result.isOk {
        AppLogger.auth.info(
          "Fresh channel flow: recreateProtocolWithMasterKey succeeded for connectId=\(connectId, privacy: .public)"
        )
        await stateManager.transitionToAuthenticated(
          membershipId: membership.membershipId.uuidString
        )
        return await establishAndPersistSecrecyChannel(
          connectId: connectId,
          accountId: accountId,
          membershipId: membership.membershipId
        )
      }
      await handleAuthenticatedProtocolFailure(
        connectId: connectId,
        accountId: accountId,
        settings: settings
      )
    }
    AppLogger.auth.info(
      "Fresh channel flow: falling back to anonymous protocol for connectId=\(connectId, privacy: .public)"
    )
    await initializeProtocolWithoutIdentity(connectId: connectId, settings: settings)
    return await establishAndPersistSecrecyChannel(
      connectId: connectId,
      accountId: nil
    )
  }

  private func establishAndPersistSecrecyChannel(
    connectId: UInt32,
    accountId: UUID?,
    membershipId: UUID? = nil
  ) async -> Result<UInt32, String> {
    AppLogger.app.info("Application init: establishSecrecyChannel connectId=\(connectId)")
    let establishResult = await bootstrapClient.establishSecrecyChannel(connectId: connectId)
    guard establishResult.isOk else {
      return establishResult.propagateErr()
    }
    if let accountId = accountId {
      AppLogger.security.debug(
        "Secrecy channel: persisting state for connectId=\(connectId, privacy: .public), accountId=\(accountId.uuidString, privacy: .public)"
      )
      let sealKeyResult = await deriveSealKey(accountId: accountId, membershipId: membershipId)
      guard let sealKey = sealKeyResult.ok() else {
        AppLogger.security.warning(
          "Secrecy channel: skipping persisted state for connectId=\(connectId, privacy: .public), reason=\(sealKeyResult.err() ?? "", privacy: .public)"
        )
        let deleteResult = await protocolStateStorage.deleteState(connectId: String(connectId))
        if deleteResult.isErr {
          AppLogger.security.warning(
            "Secrecy channel: failed to clear stale state for connectId=\(connectId, privacy: .public), error=\(deleteResult.err() ?? "", privacy: .public)"
          )
        }
        return .ok(connectId)
      }

      let accountIdData = accountId.protobufBytes
      await persistSessionState(
        connectId: connectId,
        accountId: accountIdData,
        sealKey: sealKey
      )
    }
    return .ok(connectId)
  }

  func initializeProtocolWithoutIdentity(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async {
    AppLogger.auth.info(
      "Protocol init: initializing anonymous identity for connectId=\(connectId, privacy: .public)")
    await stateManager.transitionToAnonymous()
    let shouldPreserveIncompleteMembership =
      settings.currentAccountId == nil
      && settings.membership != nil
    if shouldPreserveIncompleteMembership {
      AppLogger.auth.info(
        "Protocol init: preserving incomplete membership for connectId=\(connectId, privacy: .public)"
      )
    } else if settings.membership != nil {
      let clearResult = await secureStorage.setMembership(nil)
      if clearResult.isErr {
        AppLogger.auth.warning(
          "Protocol init: failed to clear membership for connectId=\(connectId, privacy: .public), error=\(clearResult.err() ?? "", privacy: .public)"
        )
      }
    }
    bootstrapClient.initiateProtocol(
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId,
      connectId: connectId
    )
  }

  func deriveSealKey(accountId: UUID?, membershipId: UUID?) async -> Result<Data, String> {
    guard let accountId else {
      return .err("Account ID missing for sealed-state key derivation")
    }
    guard let membershipId else {
      return .err("Membership ID missing for sealed-state key derivation")
    }
    return await identityService.deriveSealedStateKey(
      forAccountId: accountId,
      membershipId: membershipId
    )
  }

  func loadMasterKey(settings: ApplicationInstanceSettings) async -> Data? {
    guard let accountId = settings.currentAccountId else {
      AppLogger.auth.debug("Master key load: accountId missing")
      return nil
    }

    let hasIdentity = await identityService.hasStoredIdentity(accountId: accountId)
    guard hasIdentity else {
      AppLogger.auth.info(
        "Master key load: no key shares for accountId=\(accountId.uuidString, privacy: .public)")
      return nil
    }

    let loadResult = await identityService.loadMasterKey(forAccountId: accountId)
    if let key = loadResult.ok() {
      AppLogger.auth.info(
        "Master key load: success accountId=\(accountId.uuidString, privacy: .public), keyBytes=\(key.count, privacy: .public)"
      )
      return key
    }
    if let error = loadResult.err() {
      AppLogger.auth.warning(
        "Master key load: failed accountId=\(accountId.uuidString, privacy: .public), error=\(error, privacy: .public)"
      )
    }
    return nil
  }

  private func shouldFallbackFromRestoreFailure(failure: String) -> Bool {
    failure.contains("session expired") || failure.contains("state mismatch")
      || failure.contains("protocol state mismatch")
  }

  private func handleRestoreFallback(
    connectId: UInt32,
    settings: ApplicationInstanceSettings,
    failure: String
  ) async {
    AppLogger.security.warning(
      "Restore fallback: clearing local state for connectId=\(connectId, privacy: .public), failure=\(failure, privacy: .public)"
    )
    bootstrapClient.clearConnection(connectId: connectId)
    let fallbackDeleteResult = await protocolStateStorage.deleteState(connectId: String(connectId))
    if fallbackDeleteResult.isErr {
      AppLogger.security.warning(
        "Restore fallback: failed to delete state for connectId=\(connectId, privacy: .public), error=\(fallbackDeleteResult.err() ?? "", privacy: .public)"
      )
    }
    if settings.membership != nil {
      let clearResult = await secureStorage.setMembership(nil)
      if clearResult.isErr {
        AppLogger.security.warning(
          "Restore fallback: failed to clear membership for connectId=\(connectId, privacy: .public), error=\(clearResult.err() ?? "", privacy: .public)"
        )
      }
    }
    await stateManager.transitionToAnonymous()
  }

  private func handleAuthenticatedProtocolFailure(
    connectId: UInt32,
    accountId: UUID,
    settings: ApplicationInstanceSettings
  ) async {
    AppLogger.auth.warning(
      "Authenticated protocol: recreate failed, cleaning local identity for accountId=\(accountId.uuidString, privacy: .public), connectId=\(connectId, privacy: .public)"
    )
    let cleanupResult = await identityService.cleanupMembershipStateWithKeys(
      accountId: accountId,
      connectId: connectId
    )
    if cleanupResult.isErr {
      AppLogger.auth.warning(
        "Authenticated protocol: cleanup failed for accountId=\(accountId.uuidString, privacy: .public), error=\(cleanupResult.err() ?? "", privacy: .public)"
      )
    }
    await initializeProtocolWithoutIdentity(connectId: connectId, settings: settings)
  }

  func handleRevokedSession(
    connectId: UInt32,
    accountId: UUID?,
    membershipId: UUID
  ) async {
    if let accountId = accountId {
      let cleanupResult = await identityService.cleanupMembershipStateWithKeys(
        accountId: accountId,
        connectId: connectId
      )
      if cleanupResult.isErr {
        AppLogger.auth.warning(
          "Revoked session: cleanup failed for accountId=\(accountId.uuidString, privacy: .public), error=\(cleanupResult.err() ?? "", privacy: .public)"
        )
      }
    } else {
      bootstrapClient.clearConnection(connectId: connectId)
      let deleteResult = await protocolStateStorage.deleteState(connectId: String(connectId))
      if deleteResult.isErr {
        AppLogger.security.warning(
          "Revoked session: failed to delete state for connectId=\(connectId, privacy: .public), error=\(deleteResult.err() ?? "", privacy: .public)"
        )
      }

      let clearMembershipResult = await secureStorage.setMembership(nil)
      if clearMembershipResult.isErr {
        AppLogger.security.warning(
          "Revoked session: failed to clear membership, error=\(clearMembershipResult.err() ?? "", privacy: .public)"
        )
      }

      let clearAccountResult = await secureStorage.setCurrentAccountId(nil)
      if clearAccountResult.isErr {
        AppLogger.security.warning(
          "Revoked session: failed to clear account ID, error=\(clearAccountResult.err() ?? "", privacy: .public)"
        )
      }
    }

    let consumeResult = await secureStorage.consumeRevocationProof(for: membershipId)
    if consumeResult.isErr {
      AppLogger.security.warning(
        "Revoked session: failed to consume revocation proof for membershipId=\(membershipId.uuidString, privacy: .public), error=\(consumeResult.err() ?? "", privacy: .public)"
      )
    }
    await stateManager.transitionToAnonymous()
  }

  private func hasRevocationProof(membershipId: String) async -> Bool {
    guard let membershipUUID = UUID(uuidString: membershipId) else {
      return false
    }
    return await secureStorage.hasRevocationProof(for: membershipUUID)
  }

  private func persistSessionState(connectId: UInt32, accountId: Data, sealKey: Data) async {
    let externalCounter = UInt64(Date().timeIntervalSince1970 * 1000)
    _ = await bootstrapClient.persistSessionState(
      connectId: connectId,
      accountId: accountId,
      sealKey: sealKey,
      externalCounter: externalCounter
    )
  }
}
