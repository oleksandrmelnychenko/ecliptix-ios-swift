// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os

final class OpaqueRegistrationService: @unchecked Sendable {

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

  func initiateRegistrationVerification(mobileNumber: String) async -> Result<
    RegistrationVerificationOutcome, String
  > {
    AppLogger.auth.info(
      "Registration: initiate verification mobile=\(mobileNumber, privacy: .private(mask: .hash))")
    let connectId = ConnectIdResolver.resolve(
      settings: secureStorageService.settings,
      exchangeType: .dataCenterEphemeralConnect
    )
    let validateResult = await authenticationRpcService.validateMobileNumberSecure(
      mobileNumber: mobileNumber,
      connectId: connectId
    )
    guard let validateResponse = validateResult.ok() else {
      let rpcError = validateResult.unwrapErr()
      AppLogger.auth.error(
        "Registration: mobile validation failed, error=\(rpcError.logDescription, privacy: .public)"
      )
      return .err(rpcError.logDescription)
    }
    guard !validateResponse.mobileNumberID.isEmpty else {
      AppLogger.auth.error("Registration: empty mobileNumberID from validation")
      return .err(ErrorI18NKeys.mobileValidationEmpty)
    }
    AppLogger.auth.debug("Registration: mobile validated, checking availability")
    let availabilityResult = await authenticationRpcService.checkMobileNumberAvailabilitySecure(
      mobileNumberId: validateResponse.mobileNumberID,
      connectId: connectId
    )
    guard let availability = availabilityResult.ok() else {
      let rpcError = availabilityResult.unwrapErr()
      AppLogger.auth.error(
        "Registration: availability check failed, error=\(rpcError.logDescription, privacy: .public)"
      )
      return .err(rpcError.logDescription)
    }
    AppLogger.auth.debug(
      "Registration: availability status=\(String(describing: availability.status), privacy: .public), canRegister=\(availability.canRegister, privacy: .public), canContinue=\(availability.canContinue, privacy: .public)"
    )
    let sessionIdData = validateResponse.mobileNumberID
    let flowResult = await resolveRegistrationFlow(
      availability: availability,
      mobileNumber: mobileNumber
    )
    guard let nextStep = flowResult.ok() else {
      let errorMessage = flowResult.err() ?? "Unknown error"
      AppLogger.auth.error(
        "Registration: flow resolution failed, error=\(errorMessage, privacy: .public)")
      return .err(errorMessage)
    }
    AppLogger.auth.info(
      "Registration: verification initiated, nextStep=\(String(describing: nextStep), privacy: .public)"
    )
    return .ok(
      RegistrationVerificationOutcome(
        sessionId: sessionIdData.base64EncodedString(),
        expiresAt: Date().addingTimeInterval(
          TimeInterval(AppConstants.Otp.registrationInitSessionExpirySeconds)),
        otpLength: AppConstants.Otp.defaultOtpCodeLength,
        retryAfterSeconds: AppConstants.Otp.defaultOtpExpirySeconds,
        nextStep: nextStep
      )
    )
  }

  private func mapAvailabilityError(statusRaw: Int) -> String {
    switch statusRaw {
    case 3, 4:
      return ErrorI18NKeys.mobileAlreadyRegistered
    case 5:
      return ErrorI18NKeys.mobileDataCorrupted
    default:
      return ErrorI18NKeys.mobileNotAvailable
    }
  }

  private func resolveRegistrationFlow(
    availability: MobileNumberAvailabilityResponse,
    mobileNumber: String
  ) async -> Result<RegistrationNextStep, String> {
    if !availability.canRegister && !availability.canContinue {
      switch availability.status {
      case .mobileNumberAvailabilityTakenActive, .mobileNumberAvailabilityTakenInactive:
        return .ok(.onboarding)
      default:
        let statusRaw = availability.status.rawValue
        let error = mapAvailabilityError(statusRaw: statusRaw)
        return .err(error)
      }
    }
    if availability.status == .mobileNumberAvailabilityIncompleteRegistration,
      availability.canContinue,
      availability.hasCreationStatus
    {
      guard availability.hasExistingMembershipID,
        let membershipId = UUID(data: availability.existingMembershipID)
      else {
        AppLogger.auth.warning(
          "Registration: incomplete status without membershipId, falling back to OTP")
        return .ok(.otp)
      }

      let accountId =
        availability.hasAccountID
        ? UUID(data: availability.accountID)
        : nil
      await storeIncompleteMembershipIfNeeded(
        membershipId: membershipId,
        mobileNumber: mobileNumber,
        accountId: accountId
      )
      switch availability.creationStatus {
      case .otpVerified:
        _ = await secureStorageService.setRegistrationCheckpoint(.otpVerified)
        return .ok(.secureKey(membershipId: membershipId))
      case .primaryCredentialSet:
        guard accountId != nil else {
          AppLogger.auth.warning(
            "Registration: primaryCredentialSet without accountId, falling back to secureKey step")
          _ = await secureStorageService.setRegistrationCheckpoint(.otpVerified)
          return .ok(.secureKey(membershipId: membershipId))
        }
        _ = await secureStorageService.setRegistrationCheckpoint(.primaryCredentialSet)
        return .ok(.pinSetup(membershipId: membershipId))
      default:
        break
      }
    }
    return .ok(.otp)
  }

  private func storeIncompleteMembershipIfNeeded(
    membershipId: UUID?,
    mobileNumber: String,
    accountId: UUID?
  ) async {
    guard let membershipId else { return }
    let membership = Membership(membershipId: membershipId, mobileNumber: mobileNumber)
    let result = await secureStorageService.setMembershipAndAccountId(
      membership: membership,
      accountId: accountId
    )
    if result.isErr {
      AppLogger.auth.warning(
        "Registration: failed to store membership/accountId for membershipId=\(membershipId.uuidString, privacy: .public), error=\(result.err() ?? "Unknown error", privacy: .public)"
      )
    }
  }

  func completeRegistration(
    membershipIdBytes: Data,
    secureKey: SecureTextBuffer
  ) async -> Result<RegistrationCompleteOutcome, String> {
    AppLogger.auth.info(
      "Registration: complete start membershipIdBytes=\(membershipIdBytes.count, privacy: .public)B"
    )
    guard let lockGeneration = stateManager.tryAcquire(membershipIdBytes) else {
      AppLogger.auth.warning("Registration: already in progress for this membershipId")
      return .err(ErrorI18NKeys.registrationInProgress)
    }
    defer { stateManager.release(membershipIdBytes, generation: lockGeneration) }

    let connectId = ConnectIdResolver.resolve(
      settings: secureStorageService.settings,
      exchangeType: .dataCenterEphemeralConnect
    )
    let serverPublicKeyResult = await secureSessionClient.getServerPublicKey(connectId: connectId)
    guard let serverPublicKey = serverPublicKeyResult.ok() else {
      let errorMessage = serverPublicKeyResult.err()?.message ?? "Unknown error"
      AppLogger.auth.error(
        "Registration: server public key failed, error=\(errorMessage, privacy: .public)")
      return .err(
        "\(AppConstants.OpaqueRegistration.failedToGetServerPublicKeyPrefix) \(errorMessage)")
    }
    guard !membershipIdBytes.isEmpty else {
      AppLogger.auth.error("Registration: empty membershipIdBytes")
      return .err(ErrorI18NKeys.membershipIdRequired)
    }
    guard secureKey.length > 0 else {
      AppLogger.auth.warning("Registration: empty secure key")
      return .err(ErrorI18NKeys.secureKeyRequired)
    }
    return await TransientErrorDetection.executeWithRetry { [self] in
      guard var secureKeyBytes = secureKey.withSecureBytes({ Data($0) }), !secureKeyBytes.isEmpty
      else {
        AppLogger.auth.warning("Registration: secure key unavailable during retry")
        return .err(ErrorI18NKeys.secureKeyRequired)
      }
      defer { OpaqueNative.secureZeroData(&secureKeyBytes) }

      return await executeRegistrationOpaqueFlow(
        membershipIdBytes: membershipIdBytes,
        secureKeyBytes: secureKeyBytes,
        serverPublicKey: serverPublicKey,
        connectId: connectId
      )
    }
  }

  private func executeRegistrationOpaqueFlow(
    membershipIdBytes: Data,
    secureKeyBytes: Data,
    serverPublicKey: Data,
    connectId: ConnectId
  ) async -> Result<RegistrationCompleteOutcome, String> {
    AppLogger.auth.debug("RegistrationOPAQUE: flow start connectId=\(connectId, privacy: .public)")
    do {
      let opaqueAgent = try agentCache.getOrCreateAgent(serverPublicKey: serverPublicKey)
      let registrationState = try opaqueAgent.createRegistrationRequest(secureKeyBytes)
      defer { registrationState.dispose() }

      guard var requestData = registrationState.getRequestCopy() else {
        AppLogger.auth.error("RegistrationOPAQUE: registration request data unavailable")
        return .err(ErrorI18NKeys.registrationRequestUnavailable)
      }
      defer { OpaqueNative.secureZeroData(&requestData) }

      var initRequest = OpaqueRegistrationInitRequest()
      initRequest.peerOprf = requestData
      initRequest.membershipID = membershipIdBytes
      let initResult = await authenticationRpcService.registrationOpaqueInit(
        request: initRequest,
        connectId: connectId
      )
      guard let initResponse = initResult.ok() else {
        let rpcError = initResult.unwrapErr()
        AppLogger.auth.error(
          "RegistrationOPAQUE: init RPC failed, error=\(rpcError.logDescription, privacy: .public)")
        return .err(rpcError.logDescription)
      }
      guard initResponse.result.rawValue == AppConstants.Opaque.resultSucceeded else {
        let message =
          initResponse.message.isEmpty
          ? ErrorI18NKeys.registrationInitFailed
          : initResponse.message
        AppLogger.auth.warning(
          "RegistrationOPAQUE: init server rejected result=\(initResponse.result.rawValue, privacy: .public), message=\(message, privacy: .public)"
        )
        return .err(message)
      }

      let responseData = initResponse.peerOprf
      guard responseData.count == OpaqueNative.REGISTRATION_RESPONSE_LENGTH else {
        AppLogger.auth.error(
          "RegistrationOPAQUE: unexpected response length \(responseData.count), expected \(OpaqueNative.REGISTRATION_RESPONSE_LENGTH)"
        )
        return .err(ErrorI18NKeys.registrationInitFailed)
      }

      let deviceServerPublicKey = Data(responseData[OpaqueNative.REGISTRATION_REQUEST_LENGTH...])
      let finalizeAgent: OpaqueAgent
      let needsDispose: Bool
      if deviceServerPublicKey == serverPublicKey {
        finalizeAgent = opaqueAgent
        needsDispose = false
      } else {
        AppLogger.auth.info(
          "RegistrationOPAQUE: server uses per-device key, creating device-specific agent")
        finalizeAgent = try OpaqueAgent(serverPublicKey: deviceServerPublicKey)
        needsDispose = true
        Self.storeDeviceOpaquePublicKey(deviceServerPublicKey)
      }
      defer { if needsDispose { finalizeAgent.dispose() } }

      var registrationRecord: Data
      registrationRecord = try finalizeAgent.finalizeRegistration(
        responseData,
        registrationState
      )
      defer { OpaqueNative.secureZeroData(&registrationRecord) }

      var completeRequest = OpaqueRegistrationCompleteRequest()
      completeRequest.peerRegistrationRecord = registrationRecord
      completeRequest.membershipID = membershipIdBytes
      let completeResult = await authenticationRpcService.registrationOpaqueComplete(
        request: completeRequest,
        connectId: connectId
      )
      guard let completeResponse = completeResult.ok() else {
        let rpcError = completeResult.unwrapErr()
        AppLogger.auth.error(
          "RegistrationOPAQUE: complete RPC failed, error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(rpcError.logDescription)
      }
      guard completeResponse.result.rawValue == AppConstants.Opaque.resultSucceeded else {
        let message =
          completeResponse.message.isEmpty
          ? ErrorI18NKeys.registrationCompleteFailed
          : completeResponse.message
        AppLogger.auth.warning(
          "RegistrationOPAQUE: complete server rejected result=\(completeResponse.result.rawValue, privacy: .public), message=\(message, privacy: .public)"
        )
        return .err(message)
      }

      var activeAccountId: UUID? = nil
      if completeResponse.hasActiveAccount {
        activeAccountId = UUID(data: completeResponse.activeAccount.accountID)
      } else if let first = completeResponse.availableAccounts.first {
        activeAccountId = UUID(data: first.accountID)
      }
      if let activeAccountId {
        let setResult = await secureStorageService.setCurrentAccountId(activeAccountId)
        if setResult.isErr {
          AppLogger.auth.warning(
            "RegistrationOPAQUE: failed to store accountId=\(activeAccountId.uuidString, privacy: .public), error=\(setResult.err() ?? "Unknown error", privacy: .public)"
          )
        }
      }
      AppLogger.auth.info(
        "RegistrationOPAQUE: complete success accountId=\(activeAccountId?.uuidString ?? "nil", privacy: .public)"
      )
      return .ok(RegistrationCompleteOutcome(activeAccountId: activeAccountId))
    } catch let error as OpaqueError {
      AppLogger.auth.error("RegistrationOPAQUE: OPAQUE error=\(error.message, privacy: .public)")
      return .err(error.message)
    } catch {
      AppLogger.auth.error(
        "RegistrationOPAQUE: unexpected error=\(error.localizedDescription, privacy: .public)")
      return .err(error.localizedDescription)
    }
  }

  private static let deviceOpaquePublicKeyKey = "ecliptix_device_opaque_pk"

  static func storeDeviceOpaquePublicKey(_ key: Data) {
    UserDefaults.standard.set(key, forKey: deviceOpaquePublicKeyKey)
  }

  static func loadDeviceOpaquePublicKey() -> Data? {
    UserDefaults.standard.data(forKey: deviceOpaquePublicKeyKey)
  }
}

struct RegistrationCompleteOutcome {

  let activeAccountId: UUID?
}

struct RegistrationVerificationOutcome {

  let sessionId: String
  let expiresAt: Date
  let otpLength: Int
  let retryAfterSeconds: Int
  let nextStep: RegistrationNextStep
}

enum RegistrationNextStep {
  case otp
  case secureKey(membershipId: UUID?)
  case pinSetup(membershipId: UUID?)
  case onboarding
}
