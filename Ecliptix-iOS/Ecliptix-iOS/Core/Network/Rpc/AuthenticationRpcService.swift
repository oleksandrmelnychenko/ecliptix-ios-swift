import CryptoKit
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class AuthenticationRpcService {

  private let transport: EventGatewayTransport
  private let secureSessionClient: any SecureSessionClient
  private let streamRequestExecutor: any SecureStreamingRequestExecuting
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private let pipeline: SecureUnaryPipeline
  private let streamManager = VerificationStreamManager()

  init(
    transport: EventGatewayTransport,
    secureSessionClient: any SecureSessionClient & SecureStreamingRequestExecuting
      & NetworkOutageControlling,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService
  ) {
    self.transport = transport
    self.secureSessionClient = secureSessionClient
    self.streamRequestExecutor = secureSessionClient
    self.connectIdProvider = connectIdProvider
    self.pipeline = SecureUnaryPipeline(
      transport: transport,
      secureSessionClient: secureSessionClient,
      log: AppLogger.auth,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
  }

  func signInInitiate(
    mobileNumber: String
  ) async -> Result<SignInInitiateResponse, RpcError> {
    var request = MobileNumberValidateRequest()
    request.mobileNumber = mobileNumber
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      return .err(.serializationFailed("sign-in request"))
    }

    let connectId = currentConnectId()
    AppLogger.auth.info(
      "Sign-in initiate: start connectId=\(connectId, privacy: .public), mobile=\(mobileNumber, privacy: .private(mask: .hash))"
    )

    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: .validateMobileNumber,
      plaintext: requestData,
      connectId: connectId
    )
    guard let decryptedPayload = decryptedResult.ok() else {
      return decryptedResult.propagateErr()
    }

    let proto: MobileNumberValidateResponse
    do {
      proto = try MobileNumberValidateResponse(serializedBytes: decryptedPayload)
    } catch {
      return .err(.deserializationFailed("sign-in response: \(error.localizedDescription)"))
    }

    let signInResponse = SignInInitiateResponse(
      sessionId: proto.mobileNumberID.base64EncodedString(),
      expiresAt: Date().addingTimeInterval(
        TimeInterval(AppConstants.Otp.defaultSessionExpirySeconds)),
      otpLength: AppConstants.Otp.defaultOtpCodeLength,
      retryAfterSeconds: AppConstants.Otp.defaultOtpExpirySeconds
    )
    AppLogger.auth.info(
      "Sign-in initiate: success connectId=\(connectId, privacy: .public), mobileNumberIDBytes=\(proto.mobileNumberID.count, privacy: .public)"
    )
    return .ok(signInResponse)
  }

  func verifyOtp(
    verificationId: String,
    otpCode: String,
    purposeRawValue: Int = 1,
    streamConnectId: UInt32 = 0,
    connectId: UInt32? = nil
  ) async -> Result<OtpVerificationResult, RpcError> {
    let mappedStreamConnectId = streamManager.tryGetActiveStream(verificationId)
    guard let effectiveStreamConnectId = mappedStreamConnectId, effectiveStreamConnectId != 0 else {
      AppLogger.auth.warning(
        "OTP verify: missing active stream connectId, provided=\(streamConnectId, privacy: .public), verificationId=\(verificationId, privacy: .private(mask: .hash))"
      )
      return .err(.unexpected("error.not_found: No active verification flow"))
    }

    var request = OtpCodeVerifyRequest()
    request.code = otpCode
    if let purpose = OtpVerificationRequestPurpose(rawValue: purposeRawValue) {
      request.purpose = purpose
    }
    AppLogger.auth.debug(
      "OTP verify: streamConnectId=\(effectiveStreamConnectId, privacy: .public), mapped=\(String(describing: mappedStreamConnectId), privacy: .public), provided=\(streamConnectId, privacy: .public), verificationId=\(verificationId, privacy: .private(mask: .hash))"
    )
    request.streamConnectID = effectiveStreamConnectId
    AppLogger.auth.info(
      "OTP verify: start unaryConnectId=\(self.transportConnectId(connectId), privacy: .public), streamConnectId=\(effectiveStreamConnectId, privacy: .public), codeLength=\(otpCode.count, privacy: .public)"
    )
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      return .err(.serializationFailed("OTP verification request"))
    }

    let transportConnectId = transportConnectId(connectId)
    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: .verifyOtp,
      plaintext: requestData,
      connectId: transportConnectId
    )
    guard let decryptedPayload = decryptedResult.ok() else {
      return decryptedResult.propagateErr()
    }

    let proto: OtpCodeVerifyResponse
    do {
      proto = try OtpCodeVerifyResponse(serializedBytes: decryptedPayload)
    } catch {
      return .err(.deserializationFailed("OTP response: \(error.localizedDescription)"))
    }
    guard proto.result == .succeeded else {
      let message = proto.message.trimmingCharacters(in: .whitespacesAndNewlines)
      return .err(
        .serverError(
          code: "otp.verification_failed", message: message.isEmpty ? "Invalid OTP code" : message))
    }
    guard proto.hasMembership,
      let membershipId = UUID(data: proto.membership.membershipID)
    else {
      return .err(.unexpected("OTP verification succeeded but membership identifier is missing"))
    }

    let accountId: UUID =
      proto.membership.accounts.first
      .flatMap { UUID(data: $0.accountID) } ?? .zero
    let verifyResult = OtpVerificationResult(
      isVerified: proto.result == .succeeded,
      accountId: accountId,
      membershipId: membershipId,
      membershipIdBytes: proto.membership.membershipID,
      authToken: Data(),
      refreshToken: Data(),
      sessionInfo: SessionInfo(
        deviceId: .zero,
        expiresAt: Date().addingTimeInterval(
          TimeInterval(AppConstants.Otp.sessionInfoDefaultExpirySeconds)),
        scopes: []
      )
    )
    streamManager.closeStream(verificationId)
    AppLogger.auth.info(
      "OTP verify: success unaryConnectId=\(transportConnectId, privacy: .public), streamConnectId=\(effectiveStreamConnectId, privacy: .public), membershipBytes=\(proto.membership.membershipID.count, privacy: .public)"
    )
    return .ok(verifyResult)
  }

  func verifyOtpStream(
    verificationId: String,
    otpCode: String,
    purposeRawValue: Int = 1,
    streamConnectId: UInt32 = 0,
    onStatusUpdate: @escaping (OtpVerificationStatus) -> Void
  ) async -> Result<OtpVerificationResult, RpcError> {
    onStatusUpdate(.validating)
    return await verifyOtp(
      verificationId: verificationId,
      otpCode: otpCode,
      purposeRawValue: purposeRawValue,
      streamConnectId: streamConnectId,
      connectId: nil
    )
  }

  func resendOtp(
    sessionId: String,
    cancellationToken: CancellationToken = .none
  ) async -> Result<ResendOtpResponse, RpcError> {
    let streamResult = await startOtpCountdownStream(
      sessionId: sessionId,
      purposeRawValue: AppConstants.Otp.purposeRegistration,
      requestTypeRawValue: AppConstants.Otp.requestTypeResend,
      connectId: currentConnectId(),
      onUpdate: { _ in },
      cancellationToken: cancellationToken
    )
    guard streamResult.isOk else {
      return streamResult.propagateErr()
    }
    return .ok(
      ResendOtpResponse(
        success: true, retryAfterSeconds: AppConstants.Otp.defaultOtpExpirySeconds,
        attemptsRemaining: AppConstants.Otp.resendAttemptsRemaining))
  }

  func initiateRecoveryVerification(
    mobileNumber: String,
    connectId: UInt32
  ) async -> Result<SignInInitiateResponse, RpcError> {
    AppLogger.auth.info(
      "Recovery verification: start mobile=\(mobileNumber, privacy: .private(mask: .hash)), connectId=\(connectId, privacy: .public)"
    )
    let validateResult = await validateMobileForRecoverySecure(
      mobileNumber: mobileNumber,
      connectId: connectId
    )
    guard let validateResponse = validateResult.ok() else {
      AppLogger.auth.warning(
        "Recovery verification: validate failed connectId=\(connectId, privacy: .public), error=\(validateResult.unwrapErr().logDescription, privacy: .public)"
      )
      return validateResult.propagateErr()
    }

    let response = SignInInitiateResponse(
      sessionId: validateResponse.mobileNumberID.base64EncodedString(),
      expiresAt: Date().addingTimeInterval(
        TimeInterval(AppConstants.Otp.defaultSessionExpirySeconds)),
      otpLength: AppConstants.Otp.defaultOtpCodeLength,
      retryAfterSeconds: AppConstants.Otp.defaultOtpExpirySeconds
    )
    AppLogger.auth.info(
      "Recovery verification: success connectId=\(connectId, privacy: .public), sessionBytes=\(validateResponse.mobileNumberID.count, privacy: .public)"
    )
    return .ok(response)
  }

  func terminateSession(
    request: AuthenticatedLogoutRequest,
    connectId: UInt32
  ) async -> Result<AuthenticatedLogoutResponse, RpcError> {
    AppLogger.auth.info("TerminateSession: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .terminateSession, request: request, connectId: connectId,
      label: "TerminateSession")
  }

  func signInOpaqueInit(
    request: OpaqueSignInInitRequest,
    connectId: UInt32
  ) async -> Result<OpaqueSignInInitResponse, RpcError> {
    AppLogger.auth.info("OPAQUE sign-in init: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .signInInitRequest, request: request, connectId: connectId,
      label: "OpaqueSignInInit")
  }

  func registrationOpaqueInit(
    request: OpaqueRegistrationInitRequest,
    connectId: UInt32
  ) async -> Result<OpaqueRegistrationInitResponse, RpcError> {
    AppLogger.auth.info("OPAQUE registration init: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .registrationInit, request: request, connectId: connectId,
      label: "OpaqueRegistrationInit")
  }

  func registrationOpaqueComplete(
    request: OpaqueRegistrationCompleteRequest,
    connectId: UInt32
  ) async -> Result<OpaqueRegistrationCompleteResponse, RpcError> {
    AppLogger.auth.info(
      "OPAQUE registration complete: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .registrationComplete, request: request, connectId: connectId,
      label: "OpaqueRegistrationComplete")
  }

  func recoveryOpaqueInit(
    request: OpaqueRecoveryInitRequest,
    connectId: UInt32
  ) async -> Result<OpaqueRecoveryInitResponse, RpcError> {
    AppLogger.auth.info("OPAQUE recovery init: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .recoveryInit, request: request, connectId: connectId,
      label: "OpaqueRecoveryInit")
  }

  func recoveryOpaqueComplete(
    request: OpaqueRecoveryCompleteRequest,
    connectId: UInt32
  ) async -> Result<OpaqueRecoveryCompleteResponse, RpcError> {
    AppLogger.auth.info("OPAQUE recovery complete: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .recoveryComplete, request: request, connectId: connectId,
      label: "OpaqueRecoveryComplete")
  }

  func signInOpaqueFinalize(
    request: OpaqueSignInFinalizeRequest,
    connectId: UInt32
  ) async -> Result<OpaqueSignInFinalizeResponse, RpcError> {
    AppLogger.auth.info("OPAQUE sign-in finalize: start connectId=\(connectId, privacy: .public)")
    return await executeTypedUnary(
      serviceType: .signInCompleteRequest, request: request, connectId: connectId,
      label: "OpaqueSignInFinalize")
  }

  func validateMobileNumberSecure(
    mobileNumber: String,
    connectId: UInt32
  ) async -> Result<MobileNumberValidateResponse, RpcError> {
    AppLogger.auth.info(
      "ValidateMobile: start connectId=\(connectId, privacy: .public), mobile=\(mobileNumber, privacy: .private(mask: .hash))"
    )
    var request = MobileNumberValidateRequest()
    request.mobileNumber = mobileNumber
    return await executeTypedUnary(
      serviceType: .validateMobileNumber, request: request, connectId: connectId,
      label: "ValidateMobile")
  }

  func validateMobileForRecoverySecure(
    mobileNumber: String,
    connectId: UInt32
  ) async -> Result<MobileNumberValidateResponse, RpcError> {
    AppLogger.auth.info(
      "ValidateMobileRecovery: start connectId=\(connectId, privacy: .public), mobile=\(mobileNumber, privacy: .private(mask: .hash))"
    )
    var request = MobileNumberValidateRequest()
    request.mobileNumber = mobileNumber
    return await executeTypedUnary(
      serviceType: .validateMobileForRecovery, request: request, connectId: connectId,
      label: "ValidateMobileRecovery")
  }

  func checkMobileNumberAvailabilitySecure(
    mobileNumberId: Data,
    connectId: UInt32
  ) async -> Result<MobileNumberAvailabilityResponse, RpcError> {
    AppLogger.auth.info("CheckMobileAvailability: start connectId=\(connectId, privacy: .public)")
    var request = MobileNumberAvailabilityRequest()
    request.mobileNumberID = mobileNumberId
    return await executeTypedUnary(
      serviceType: .checkMobileNumberAvailability, request: request, connectId: connectId,
      label: "CheckMobileAvailability")
  }

  func startOtpCountdownStream(
    sessionId: String,
    purposeRawValue: Int,
    requestTypeRawValue: Int = AppConstants.Otp.requestTypeSend,
    connectId: UInt32,
    onUpdate: @escaping (OtpCountdownUpdate) -> Void,
    cancellationToken: CancellationToken = .none
  ) async -> Result<Unit, RpcError> {
    guard let mobileNumberId = Data(base64Encoded: sessionId), !mobileNumberId.isEmpty else {
      AppLogger.auth.warning("OTP stream: invalid sessionId input")
      return .err(.unexpected("Invalid OTP session identifier"))
    }

    let streamProtocolResult = await secureSessionClient.ensureProtocolForStreaming()
    guard let streamConnectId = streamProtocolResult.ok() else {
      let fallbackError = streamProtocolResult.err() ?? ""
      AppLogger.auth.warning(
        "OTP stream: failed to establish streaming session, error=\(fallbackError, privacy: .public)"
      )
      return .err(.sessionRecoveryFailed("streaming session: \(fallbackError)"))
    }
    streamManager.registerStream(sessionId: sessionId, connectId: streamConnectId)
    AppLogger.auth.info(
      "OTP stream: start streamConnectId=\(streamConnectId, privacy: .public), unaryConnectId=\(connectId, privacy: .public), purpose=\(purposeRawValue, privacy: .public), type=\(requestTypeRawValue, privacy: .public)"
    )

    var request = OtpVerificationRequest()
    request.mobileNumberID = mobileNumberId
    if let purpose = OtpVerificationRequestPurpose(rawValue: purposeRawValue) {
      request.purpose = purpose
    }
    if let requestType = OtpVerificationRequestType(rawValue: requestTypeRawValue) {
      request.type = requestType
    }

    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      return .err(.serializationFailed("OTP stream request"))
    }

    let streamResult = await streamRequestExecutor.executeReceiveStreamRequest(
      connectId: streamConnectId,
      serviceType: .initiateVerification,
      plainBuffer: requestData,
      onStreamItem: { [weak self] streamPayload in
        let update: OtpCountdownUpdate
        do {
          update = try OtpCountdownUpdate(serializedBytes: streamPayload)
        } catch {
          AppLogger.auth.warning(
            "OTP stream: failed to parse countdown update bytes=\(streamPayload.count, privacy: .public), connectId=\(streamConnectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
          )
          let parseError = "Failed to parse OTP countdown update: \(error.localizedDescription)"
          return .err(.invalidRequestType(parseError))
        }
        if !update.sessionID.isEmpty {
          let flowSessionId = update.sessionID.base64EncodedString()
          self?.streamManager.processUpdate(
            sessionId: flowSessionId,
            connectId: streamConnectId,
            status: update.status
          )
        }
        onUpdate(update)
        return .ok(.value)
      },
      allowDuplicates: true,
      cancellationToken: cancellationToken,
      exchangeType: .serverStreaming
    )
    if let failure = streamResult.err() {
      streamManager.closeStream(sessionId)
      if failure.failureType == .protocolStateMismatch {
        AppLogger.auth.warning(
          "OTP stream: clearing stale streaming session streamConnectId=\(streamConnectId, privacy: .public)"
        )
        secureSessionClient.clearConnection(connectId: streamConnectId)
      }
      AppLogger.auth.warning(
        "OTP stream: failed streamConnectId=\(streamConnectId, privacy: .public), error=\(failure.message, privacy: .public)"
      )
      return .err(.unexpected(failure.message))
    }
    streamManager.closeStream(sessionId)
    AppLogger.auth.info(
      "OTP stream: completed streamConnectId=\(streamConnectId, privacy: .public), purpose=\(purposeRawValue, privacy: .public), type=\(requestTypeRawValue, privacy: .public)"
    )
    return .ok(.value)
  }

  private func executeTypedUnary<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    serviceType: RpcServiceType,
    request: Request,
    connectId: UInt32,
    label: String
  ) async -> Result<Response, RpcError> {
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      AppLogger.auth.error(
        "\(label): serialize failed connectId=\(connectId, privacy: .public)")
      return .err(.serializationFailed("\(label) request"))
    }

    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: serviceType,
      plaintext: requestData,
      connectId: connectId
    )
    guard let decryptedPayload = decryptedResult.ok() else {
      AppLogger.auth.warning(
        "\(label): secure unary failed connectId=\(connectId, privacy: .public), error=\(decryptedResult.unwrapErr().logDescription, privacy: .public)"
      )
      return decryptedResult.propagateErr()
    }

    let response: Response
    do {
      response = try Response(serializedBytes: decryptedPayload)
    } catch {
      AppLogger.auth.error(
        "\(label): parse failed connectId=\(connectId, privacy: .public)")
      return .err(.deserializationFailed("\(label) response: \(error.localizedDescription)"))
    }
    AppLogger.auth.info("\(label): success connectId=\(connectId, privacy: .public)")
    return .ok(response)
  }

  private func transportConnectId(_ explicitConnectId: UInt32?) -> UInt32 {
    explicitConnectId ?? currentConnectId()
  }

  private func currentConnectId() -> UInt32 {
    connectIdProvider(.dataCenterEphemeralConnect)
  }

  func closeVerificationStream(_ sessionId: String) {
    streamManager.closeStream(sessionId)
  }
}

private typealias OtpVerificationRequestPurpose = OtpVerificationPurpose
private typealias OtpVerificationRequestType = OtpVerificationRequest.TypeEnum
struct SignInInitiateResponse {

  let sessionId: String
  let expiresAt: Date
  let otpLength: Int
  let retryAfterSeconds: Int
}

enum OtpVerificationStatus: String {
  case validating = "VALIDATING"
  case checkingRateLimit = "CHECKING_RATE_LIMIT"
  case verifyingSignature = "VERIFYING_SIGNATURE"
  case preparingSession = "PREPARING_SESSION"
  case completed = "COMPLETED"
  case failed = "FAILED"
  case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
  case expired = "EXPIRED"
  case invalidCode = "INVALID_CODE"
  var description: String {
    switch self {
    case .validating: return "Validating code..."
    case .checkingRateLimit: return "Checking rate limits..."
    case .verifyingSignature: return "Verifying signature..."
    case .preparingSession: return "Preparing session..."
    case .completed: return "Verification completed"
    case .failed: return "Verification failed"
    case .rateLimitExceeded: return "Too many attempts"
    case .expired: return "Code expired"
    case .invalidCode: return "Invalid code"
    }
  }
}

struct OtpVerificationResult {

  let isVerified: Bool
  let accountId: UUID
  let membershipId: UUID
  let membershipIdBytes: Data
  let authToken: Data
  let refreshToken: Data
  let sessionInfo: SessionInfo
}

struct SessionInfo {

  let deviceId: UUID
  let expiresAt: Date
  let scopes: [String]
}

struct ProfileNameAvailabilityResult {

  let isAvailable: Bool
  let reason: String
}

struct ResendOtpResponse {

  let success: Bool
  let retryAfterSeconds: Int
  let attemptsRemaining: Int
}
