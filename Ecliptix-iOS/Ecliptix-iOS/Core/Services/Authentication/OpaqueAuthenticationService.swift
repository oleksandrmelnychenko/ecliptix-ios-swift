// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import EcliptixProtos
import Foundation
import os.log

final class OpaqueAuthenticationService: @unchecked Sendable {

  private let secureSessionClient: any SecureSessionClient & SessionRecoveryCoordinating
  private let outageController: any NetworkOutageControlling
  private let authenticationRpcService: AuthenticationRpcService
  private let identityService: IdentityService
  private let secureStorageService: SecureStorageService
  private let agentCache = OpaqueAgentCache()

  init(
    secureSessionClient: any SecureSessionClient & NetworkOutageControlling
      & SessionRecoveryCoordinating,
    authenticationRpcService: AuthenticationRpcService,
    identityService: IdentityService,
    secureStorageService: SecureStorageService
  ) {
    self.secureSessionClient = secureSessionClient
    self.outageController = secureSessionClient
    self.authenticationRpcService = authenticationRpcService
    self.identityService = identityService
    self.secureStorageService = secureStorageService
  }

  func signIn(
    mobileNumber: String,
    secureKey: SecureTextBuffer,
    connectId: ConnectId
  ) async -> Result<SignInOutcome, AuthenticationFailure> {
    AppLogger.auth.info(
      "OpaqueSignIn: start connectId=\(connectId, privacy: .public), mobile=\(mobileNumber, privacy: .private(mask: .hash))"
    )
    guard !mobileNumber.isEmpty else {
      AppLogger.auth.warning("OpaqueSignIn: empty mobile number")
      return .err(.mobileNumberRequired(ErrorI18NKeys.mobileNumberRequired))
    }
    guard secureKey.length > 0 else {
      AppLogger.auth.warning("OpaqueSignIn: empty secure key")
      return .err(.secureKeyRequired(ErrorI18NKeys.secureKeyRequired))
    }
    guard !Task.isCancelled else {
      return .err(.networkRequestFailed("Sign-in cancelled"))
    }

    let activeConnectIdResult = await ensureActiveSession(preferredConnectId: connectId)
    guard let activeConnectId = activeConnectIdResult.ok() else {
      let errorMessage = activeConnectIdResult.err() ?? "Unknown error"
      AppLogger.auth.error(
        "OpaqueSignIn: session establishment failed, error=\(errorMessage, privacy: .public)")
      return .err(.networkRequestFailed(errorMessage))
    }
    AppLogger.auth.debug(
      "OpaqueSignIn: session ready activeConnectId=\(activeConnectId, privacy: .public)")
    let serverPublicKeyResult = await secureSessionClient.getServerPublicKey(
      connectId: activeConnectId)
    guard let serverPublicKey = serverPublicKeyResult.ok() else {
      let errorMessage = serverPublicKeyResult.err()?.message ?? "Unknown error"
      AppLogger.auth.error(
        "OpaqueSignIn: server public key fetch failed, error=\(errorMessage, privacy: .public)")
      return .err(.networkRequestFailed(errorMessage))
    }

    let effectivePublicKey: Data
    if let deviceKey = OpaqueRegistrationService.loadDeviceOpaquePublicKey(),
      deviceKey.count == OpaqueNative.PUBLIC_KEY_LENGTH
    {
      effectivePublicKey = deviceKey
      AppLogger.auth.info("OpaqueSignIn: using stored device-specific OPAQUE key")
    } else {
      effectivePublicKey = serverPublicKey
      AppLogger.auth.debug("OpaqueSignIn: using global server public key (no device key stored)")
    }
    do {
      let opaqueAgent = try agentCache.getOrCreateAgent(serverPublicKey: effectivePublicKey)
      AppLogger.auth.debug("OpaqueSignIn: generating KE1")
      guard var secureKeyData = secureKey.withSecureBytes({ Data($0) }), !secureKeyData.isEmpty
      else {
        AppLogger.auth.warning("OpaqueSignIn: secure key unavailable while generating KE1")
        return .err(.secureKeyRequired(ErrorI18NKeys.secureKeyRequired))
      }
      defer { OpaqueNative.secureZeroData(&secureKeyData) }

      let ke1 = try opaqueAgent.generateKe1(secureKeyData)
      defer { ke1.dispose() }

      guard var ke1Data = ke1.getKeyExchangeDataCopy() else {
        return .err(.unexpectedError(ErrorI18NKeys.keyExchangeUnavailable))
      }
      defer { OpaqueNative.secureZeroData(&ke1Data) }

      var initRequest = OpaqueSignInInitRequest()
      initRequest.mobileNumber = mobileNumber
      initRequest.peerOprf = ke1Data
      let initResult = await authenticationRpcService.signInOpaqueInit(
        request: initRequest,
        connectId: activeConnectId
      )
      guard let initResponse = initResult.ok() else {
        let rpcError = initResult.unwrapErr()
        AppLogger.auth.error(
          "OpaqueSignIn: OPAQUE init RPC failed, error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(.networkRequestFailed(rpcError.logDescription))
      }
      AppLogger.auth.debug(
        "OpaqueSignIn: OPAQUE init response result=\(initResponse.result.rawValue, privacy: .public)"
      )
      let initValidation = mapOpaqueOperationResult(
        rawValue: initResponse.result.rawValue,
        message: initResponse.message
      )
      if case .err(let failure) = initValidation {
        AppLogger.auth.warning(
          "OpaqueSignIn: OPAQUE init server rejected, failureType=\(String(describing: failure.failureType), privacy: .public)"
        )
        return .err(failure)
      }
      guard !Task.isCancelled else {
        return .err(.networkRequestFailed("Sign-in cancelled"))
      }
      AppLogger.auth.debug("OpaqueSignIn: generating KE3")
      var ke2 = initResponse.serverOprfResponse
      defer { OpaqueNative.secureZeroData(&ke2) }

      var ke3 = try opaqueAgent.generateKe3(ke2, ke1)
      defer { OpaqueNative.secureZeroData(&ke3) }

      var (sessionKey, rawMasterKey) = try opaqueAgent.deriveBaseMasterKey(ke1)
      defer { OpaqueNative.secureZeroData(&sessionKey) }

      defer { OpaqueNative.secureZeroData(&rawMasterKey) }

      var masterKey = try normalizeMasterKey(rawMasterKey)
      defer { OpaqueNative.secureZeroData(&masterKey) }

      var finalizeRequest = OpaqueSignInFinalizeRequest()
      finalizeRequest.mobileNumber = mobileNumber
      finalizeRequest.clientMac = ke3
      finalizeRequest.serverStateToken = initResponse.serverStateToken
      let finalizeResult = await authenticationRpcService.signInOpaqueFinalize(
        request: finalizeRequest,
        connectId: activeConnectId
      )
      guard let finalizeResponse = finalizeResult.ok() else {
        let rpcError = finalizeResult.unwrapErr()
        AppLogger.auth.error(
          "OpaqueSignIn: OPAQUE finalize RPC failed, error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(.networkRequestFailed(rpcError.logDescription))
      }
      AppLogger.auth.debug(
        "OpaqueSignIn: OPAQUE finalize response result=\(finalizeResponse.result.rawValue, privacy: .public)"
      )
      let finalizeValidation = mapOpaqueOperationResult(
        rawValue: finalizeResponse.result.rawValue,
        message: finalizeResponse.message
      )
      if case .err(let failure) = finalizeValidation {
        AppLogger.auth.warning(
          "OpaqueSignIn: OPAQUE finalize server rejected, failureType=\(String(describing: failure.failureType), privacy: .public)"
        )
        return .err(failure)
      }
      guard finalizeResponse.hasMembership else {
        AppLogger.auth.error("OpaqueSignIn: finalize response missing membership")
        return .err(.unexpectedError(ErrorI18NKeys.membershipMissing))
      }

      let membershipIdData = finalizeResponse.membership.membershipID
      guard IdentifierValidation.isValidGuidIdentifier(membershipIdData),
        let membershipId = UUID(data: membershipIdData)
      else {
        return .err(.invalidMembershipIdentifier(ErrorI18NKeys.invalidMembershipId))
      }

      let accountIdData =
        finalizeResponse.hasActiveAccount
        ? finalizeResponse.activeAccount.accountID
        : finalizeResponse.membership.accounts.first?.accountID ?? Data()
      guard IdentifierValidation.isValidGuidIdentifier(accountIdData),
        let accountId = UUID(data: accountIdData)
      else {
        return .err(.invalidMembershipIdentifier(ErrorI18NKeys.invalidAccountId))
      }
      AppLogger.auth.info(
        "OpaqueSignIn: identity resolved membershipId=\(membershipId.uuidString, privacy: .public), accountId=\(accountId.uuidString, privacy: .public)"
      )
      let saveIdentityResult = await identityService.saveMasterKey(
        masterKey, forAccountId: accountId)
      guard saveIdentityResult.isOk else {
        let errorMessage = saveIdentityResult.err() ?? "Unknown error"
        AppLogger.auth.error(
          "OpaqueSignIn: master key save failed, error=\(errorMessage, privacy: .public)")
        return .err(.identityStorageFailed(errorMessage))
      }

      let creationStatus: SignInCreationStatus
      if finalizeResponse.membership.hasCreationStatus {
        switch finalizeResponse.membership.creationStatus {
        case .primaryCredentialSet:
          creationStatus = .primaryCredentialSet
        default:
          AppLogger.auth.warning(
            "OpaqueSignIn: unexpected creation status \(finalizeResponse.membership.creationStatus.rawValue, privacy: .public), defaulting to primaryCredentialSet"
          )
          creationStatus = .primaryCredentialSet
        }
      } else {
        creationStatus = .primaryCredentialSet
      }

      let membership = Membership(
        membershipId: membershipId,
        mobileNumber: mobileNumber
      )
      let checkpoint: RegistrationCheckpoint
      let currentCheckpoint = secureStorageService.settings?.registrationCheckpoint
      switch currentCheckpoint {
      case .pinCredentialSet, .profileCompleted:
        checkpoint = currentCheckpoint!
      default:
        checkpoint = .primaryCredentialSet
      }
      let persistStateResult = await secureStorageService.setRegistrationState(
        membership: membership,
        accountId: accountId,
        checkpoint: checkpoint
      )
      guard persistStateResult.isOk else {
        let errorMessage = persistStateResult.err() ?? "Unknown error"
        AppLogger.auth.error(
          "OpaqueSignIn: failed to persist auth state, error=\(errorMessage, privacy: .public)")
        return .err(.identityStorageFailed(errorMessage))
      }
      AppLogger.auth.debug("OpaqueSignIn: recreating protocol session")
      let recreateResult = await recreateProtocolWithRetry(
        masterKey: masterKey,
        membershipId: membershipId,
        accountId: accountId,
        connectId: activeConnectId
      )
      guard recreateResult.isOk else {
        let errorMessage = recreateResult.err() ?? "Unknown error"
        AppLogger.auth.error(
          "OpaqueSignIn: protocol recreation failed, error=\(errorMessage, privacy: .public)")
        return .err(.networkRequestFailed(errorMessage))
      }
      AppLogger.auth.info(
        "OpaqueSignIn: complete success membershipId=\(membershipId.uuidString, privacy: .public), creationStatus=\(String(describing: creationStatus), privacy: .public)"
      )
      return .ok(SignInOutcome(creationStatus: creationStatus))
    } catch let error as OpaqueError {
      AppLogger.auth.error(
        "OpaqueSignIn: OPAQUE error type=\(String(describing: error), privacy: .public)")
      switch error {
      case .authenticationError, .invalidInput, .validationError:
        return .err(.invalidCredentials(ErrorI18NKeys.invalidCredentials))
      case .invalidPublicKey, .cryptoError, .memoryError, .unknownError:
        return .err(.unexpectedError(error.message))
      }
    } catch {
      AppLogger.auth.error(
        "OpaqueSignIn: unexpected error=\(error.localizedDescription, privacy: .public)")
      return .err(.unexpectedError(error.localizedDescription))
    }
  }

  private func mapOpaqueOperationResult(
    rawValue: Int,
    message: String
  ) -> Result<Unit, AuthenticationFailure> {
    switch rawValue {
    case AppConstants.Opaque.resultSucceeded:
      return .ok(Unit.value)
    case AppConstants.Opaque.resultInvalidCredentials:
      return .err(.invalidCredentials(message.isEmpty ? ErrorI18NKeys.invalidCredentials : message))
    case AppConstants.Opaque.resultAttemptsExceeded:
      return .err(
        .loginAttemptExceeded(message.isEmpty ? ErrorI18NKeys.loginAttemptExceeded : message))
    case AppConstants.Opaque.resultRegistrationRequired:
      return .err(
        .registrationRequired(message.isEmpty ? ErrorI18NKeys.registrationRequired : message))
    default:
      if !message.isEmpty {
        return .err(.unexpectedError(message))
      }
      return .err(.unexpectedError(ErrorI18NKeys.opaqueOperationFailed))
    }
  }

  func ensureActiveSession(preferredConnectId: ConnectId) async -> Result<ConnectId, String> {
    if secureSessionClient.activeSession(connectId: preferredConnectId) != nil {
      return .ok(preferredConnectId)
    }

    let settings = secureStorageService.settings
    let deviceId = settings?.deviceId ?? NetworkConfiguration.default.deviceId
    let appInstanceId = settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    AppLogger.network.debug(
      "No active session for connectId=\(preferredConnectId), establishing secrecy channel")
    let establishResult = await secureSessionClient.coordinatedEstablishSecrecyChannel(
      connectId: preferredConnectId,
      exchangeType: .dataCenterEphemeralConnect,
      prepareProtocol: { [self, deviceId, appInstanceId] in
        secureSessionClient.initiateProtocol(
          deviceId: deviceId,
          appInstanceId: appInstanceId,
          connectId: preferredConnectId
        )
      }
    )
    guard establishResult.isOk else {
      return .err(
        "Failed to establish secure session for connectId \(preferredConnectId): \(establishResult.err() ?? "Unknown error")"
      )
    }
    guard secureSessionClient.activeSession(connectId: preferredConnectId) != nil else {
      return .err(
        "Secure session still missing after establish for connectId \(preferredConnectId)")
    }
    return .ok(preferredConnectId)
  }
}

extension OpaqueAuthenticationService {

  fileprivate func normalizeMasterKey(_ masterKey: Data) throws -> Data {
    if masterKey.count == EPPConstants.SEED_LENGTH {
      return masterKey
    }
    if masterKey.count == AppConstants.Crypto.masterKeyBytes64 {
      let inputKey = SymmetricKey(data: masterKey)
      let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKey,
        info: Data("ecliptix-master-key-normalize-v1".utf8),
        outputByteCount: EPPConstants.SEED_LENGTH
      )
      return derived.withUnsafeBytes { Data($0) }
    }
    throw OpaqueError.invalidInput(
      "Unsupported master key length: expected \(EPPConstants.SEED_LENGTH) or \(AppConstants.Crypto.masterKeyBytes64), got \(masterKey.count)"
    )
  }

  fileprivate func recreateProtocolWithRetry(
    masterKey: Data,
    membershipId: UUID,
    accountId: UUID,
    connectId: ConnectId,
    maxAttempts: Int = 3
  ) async -> Result<Unit, String> {
    var lastError = ""
    for attempt in 1...maxAttempts {
      AppLogger.auth.debug(
        "RecreateProtocol: attempt \(attempt, privacy: .public)/\(maxAttempts, privacy: .public) connectId=\(connectId, privacy: .public)"
      )
      let result = await secureSessionClient.recreateProtocolWithMasterKey(
        masterKey: masterKey,
        membershipId: membershipId,
        accountId: accountId,
        connectId: connectId
      )
      if result.isOk {
        AppLogger.auth.info(
          "RecreateProtocol: success on attempt \(attempt, privacy: .public) connectId=\(connectId, privacy: .public)"
        )
        outageController.exitOutage()
        return result
      }
      lastError = result.err() ?? "Unknown error"
      AppLogger.auth.warning(
        "RecreateProtocol: attempt \(attempt, privacy: .public) failed, error=\(lastError, privacy: .public)"
      )
      guard attempt < maxAttempts, TransientErrorDetection.isTransient(lastError) else {
        outageController.exitOutage()
        break
      }
      outageController.clearExhaustedOperations()
      let delay = TransientErrorDetection.computeExponentialDelay(attempt: attempt)
      AppLogger.auth.debug("RecreateProtocol: retrying in \(delay, privacy: .public)s")
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    AppLogger.auth.error(
      "RecreateProtocol: exhausted all attempts connectId=\(connectId, privacy: .public), lastError=\(lastError, privacy: .public)"
    )
    return .err(lastError)
  }
}

enum SignInCreationStatus {
  case primaryCredentialSet
}

struct SignInOutcome {

  let creationStatus: SignInCreationStatus
}
