import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

extension OtpVerificationViewModel {

  func initiateOtpSession(countdownVersion: Int64, requestTypeRawValue: Int) async {
    guard let sessionId = originalMobileNumberSessionId ?? verificationSessionId, !sessionId.isEmpty
    else {
      publishError(String(localized: "No verification session available"))
      return
    }
    clearOtpStreamTask()
    otpStreamCancellationToken.cancel()
    otpStreamCancellationToken = CancellationToken()
    let connectId = resolveOtpConnectId()
    replaceOtpStreamTask(with: Task { [weak self] in
      guard let self else { return }
      let result = await authService.startOtpCountdownStream(
        sessionId: sessionId,
        purposeRawValue: otpPurposeRawValue(),
        requestTypeRawValue: requestTypeRawValue,
        connectId: connectId,
        onUpdate: { [weak self] update in
          Task { @MainActor [weak self] in
            self?.handleCountdownUpdate(update, version: countdownVersion)
          }
        },
        cancellationToken: otpStreamCancellationToken
      )
      if let rpcError = result.err() {
        let errorDesc = rpcError.logDescription
        guard !errorDesc.lowercased().contains("cancel") else { return }
        await MainActor.run {
          if requestTypeRawValue == AppConstants.Otp.requestTypeResend {
            self.handleResendError(errorDesc)
          } else {
            self.handleInitialOtpStreamError(errorDesc)
          }
        }
      }
    })
  }

  func handleSuccessfulVerification(_ verification: OtpVerificationResult) async {
    if flowContext == .registration {
      let membership = Membership(
        membershipId: verification.membershipId,
        mobileNumber: mobileNumber
      )
      let saveResult = await secureStorageService.setRegistrationState(
        membership: membership,
        accountId: verification.accountId.isZero ? nil : verification.accountId,
        checkpoint: .otpVerified
      )
      if saveResult.isErr {
        AppLogger.auth.warning(
          "OTP VM: failed to persist verification state, error=\(saveResult.err() ?? "", privacy: .public)"
        )
      }
    }
    cleanupSession()
    onVerificationSucceeded(verification)
    alreadyVerifiedHandled = true
    invalidateCountdown()
  }

  func handleAlreadyVerified() async {
    guard let sessionId = verificationSessionId,
      let mobileNumberId = Data(base64Encoded: sessionId),
      !mobileNumberId.isEmpty
    else {
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectShortDelaySeconds,
        title: String(localized: "Session Not Found"),
        subtitle: String(localized: "Returning to start")
      )
      return
    }

    let availabilityResult = await authService.checkMobileNumberAvailabilitySecure(
      mobileNumberId: mobileNumberId,
      connectId: currentConnectId()
    )
    guard let availability = availabilityResult.ok() else {
      publishError(
        availabilityResult.err()?.logDescription ?? String(localized: "Session not found"))
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectShortDelaySeconds,
        title: String(localized: "Session Not Found"),
        subtitle: String(localized: "Returning to start")
      )
      return
    }
    guard availability.hasExistingMembershipID,
      let membershipId = UUID(data: availability.existingMembershipID)
    else {
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectShortDelaySeconds,
        title: String(localized: "Session Not Found"),
        subtitle: String(localized: "Returning to start")
      )
      return
    }

    let accountId =
      availability.hasAccountID
      ? (UUID(data: availability.accountID) ?? .zero)
      : .zero
    let verification = OtpVerificationResult(
      isVerified: true,
      accountId: accountId,
      membershipId: membershipId,
      membershipIdBytes: availability.existingMembershipID,
      authToken: Data(),
      refreshToken: Data(),
      sessionInfo: SessionInfo(
        deviceId: .zero,
        expiresAt: Date().addingTimeInterval(
          TimeInterval(AppConstants.Otp.sessionInfoDefaultExpirySeconds)),
        scopes: []
      )
    )
    await handleSuccessfulVerification(verification)
  }

  func handleStreamingStatus(_ status: OtpVerificationStatus) {
    switch status {
    case .validating:
      errorMessage = String(localized: "Validating code...")
      hasError = false
    case .checkingRateLimit:
      errorMessage = String(localized: "Checking rate limits...")
      hasError = false
    case .verifyingSignature:
      errorMessage = String(localized: "Verifying signature...")
      hasError = false
    case .preparingSession:
      errorMessage = String(localized: "Preparing session...")
      hasError = false
    case .completed:
      errorMessage = ""
      hasError = false
    case .failed: publishError(String(localized: "Verification failed"))
    case .rateLimitExceeded: handleRateLimitExceeded()
    case .expired: handleExpiredStatus()
    case .invalidCode: publishError(String(localized: "Invalid OTP code"))
    }
  }

  func handleCountdownUpdate(_ update: OtpCountdownUpdate, version: Int64) {
    guard isCountdownVersionCurrent(version) else { return }
    hasValidSession = true
    AppLogger.auth.debug(
      "OTP VM: stream update status=\(update.status.rawValue, privacy: .public), seconds=\(update.secondsRemaining, privacy: .public), alreadyVerified=\(update.alreadyVerified, privacy: .public), messageKey=\(update.hasMessageKey ? update.messageKey : "-", privacy: .public), context=\(String(describing: self.flowContext), privacy: .public)"
    )
    if !update.sessionID.isEmpty {
      let streamSessionId = update.sessionID.base64EncodedString()
      if originalMobileNumberSessionId == nil {
        originalMobileNumberSessionId = streamSessionId
      }
      verificationSessionId = streamSessionId
    }
    if update.alreadyVerified {
      guard !alreadyVerifiedHandled else { return }
      alreadyVerifiedHandled = true
      invalidateCountdown()
      currentStatus = .active
      secondsRemaining = 0
      updateRemainingTimeDisplay()
      replaceOtpStreamTask(with: Task { [weak self] in
        await self?.handleAlreadyVerified()
      })
      return
    }

    var effectiveStatus = update.status
    var cooldownOverrideSeconds: UInt?
    if update.hasMessageKey, !update.messageKey.isEmpty {
      let normalizedKey = update.messageKey.trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
      if normalizedKey == VerificationMessageKeys.verificationFlowExpired {
        effectiveStatus = .otpCountdownStatusSessionExpired
      } else if normalizedKey == VerificationMessageKeys.otpExpired {
        effectiveStatus = .otpCountdownStatusExpired
      } else if normalizedKey == VerificationMessageKeys.resendCooldown {
        effectiveStatus = .otpCountdownStatusResendCooldown
      } else if VerificationMessageKeys.isRateLimitKey(normalizedKey) {
        effectiveStatus = .otpCountdownStatusMaxAttemptsReached
      }
    }
    if effectiveStatus == .otpCountdownStatusFailed,
      let extractedSeconds = Self.tryExtractCooldownSeconds(update.message)
    {
      effectiveStatus = .otpCountdownStatusResendCooldown
      cooldownOverrideSeconds = UInt(extractedSeconds)
    }
    switch effectiveStatus {
    case .otpCountdownStatusActive:
      if isResending {
        isResending = false
        showResendSuccess()
      }
      currentStatus = .active
      secondsRemaining = UInt(max(0, update.secondsRemaining))
      updateRemainingTimeDisplay()
      startCountdownTask(version: version)
    case .otpCountdownStatusExpired:
      handleExpiredStatus()
    case .otpCountdownStatusResendCooldown:
      currentStatus = .resendCooldown
      cooldownBufferSeconds = cooldownOverrideSeconds ?? UInt(max(0, update.secondsRemaining))
      startCooldownTask()
    case .otpCountdownStatusFailed:
      let msg = update.message.isEmpty ? String(localized: "Verification failed") : update.message
      if isRateLimitOrExhaustedError(msg) {
        handleRateLimitExceeded()
      } else {
        currentStatus = .failed
        hasValidSession = false
        publishError(msg)
        startAutoRedirect(
          seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
          title: String(localized: "Verification Failed"),
          subtitle: String(localized: "Returning to start")
        )
      }
    case .otpCountdownStatusNotFound:
      currentStatus = .notFound
      publishError(
        update.message.isEmpty
          ? String(localized: "Verification session not found") : update.message)
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Session Not Found"),
        subtitle: String(localized: "Returning to start")
      )
    case .otpCountdownStatusMaxAttemptsReached:
      handleRateLimitExceeded()
    case .otpCountdownStatusSessionExpired:
      currentStatus = .sessionExpired
      publishError(update.message.isEmpty ? String(localized: "Session expired") : update.message)
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Session Expired"),
        subtitle: String(localized: "Returning to start")
      )
    case .otpCountdownStatusServerUnavailable:
      currentStatus = .serverUnavailable
      publishError(
        update.message.isEmpty ? String(localized: "Server unavailable") : update.message)
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Server Unavailable"),
        subtitle: String(localized: "Please try again later")
      )
    case .otpCountdownStatusUnspecified, .UNRECOGNIZED:
      AppLogger.auth.warning(
        "OTP VM: unrecognized countdown status rawValue=\(effectiveStatus.rawValue, privacy: .public), message=\(update.message, privacy: .public)"
      )
    }
  }

  private static let cooldownRegex: NSRegularExpression? = {
    try? NSRegularExpression(pattern: #"\((\d+)s\)"#)
  }()

  static func tryExtractCooldownSeconds(_ message: String) -> Int? {
    guard !message.isEmpty,
      let regex = cooldownRegex,
      let match = regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)),
      let range = Range(match.range(at: 1), in: message),
      let seconds = Int(message[range]),
      seconds > 0
    else { return nil }
    return seconds
  }

  func handleResendError(_ error: String) {
    guard !alreadyVerifiedHandled, !containsCaseInsensitive(error, "cancel") else { return }
    // If a stream update already set the countdown to active, don't clobber it —
    // the "error" is just the server closing the stream after sending the update.
    if currentStatus == .active && secondsRemaining > 0 { return }
    if isServerUnavailableError(error) {
      publishError(error)
      hasValidSession = false
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Server Error"),
        subtitle: String(localized: "Please try again later"), message: error)
    } else {
      publishError(ServerErrorMapper.userFacingMessage(error))
      secondsRemaining = 0
      currentStatus = .expired
    }
  }

  func isRateLimitOrExhaustedError(_ error: String) -> Bool {
    let keywords = [
      "rate limit", "rate_limit", "exhausted", "too many", "try again later", "locked",
      "attempts exceeded",
    ]
    return keywords.contains { error.lowercased().contains($0) }
  }

  func handleInitialOtpStreamError(_ error: String) {
    guard !alreadyVerifiedHandled, !containsCaseInsensitive(error, "cancel") else { return }
    if containsCaseInsensitive(error, "not_found") || containsCaseInsensitive(error, "not found") {
      currentStatus = .notFound
      publishError(error.isEmpty ? String(localized: "Verification session not found") : error)
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectShortDelaySeconds,
        title: String(localized: "Session Not Found"),
        subtitle: String(localized: "Returning to start")
      )
      return
    }
    if isRateLimitOrExhaustedError(error) {
      currentStatus = .maxAttemptsReached
      isMaxAttemptsReached = true
      hasValidSession = false
      cancelAllTasks()
      publishError(error)
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Too Many Attempts"),
        subtitle: String(localized: "Please try again later")
      )
      return
    }
    if isServerUnavailableError(error) {
      publishError(error)
      hasValidSession = false
      startAutoRedirect(
        seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
        title: String(localized: "Server Error"),
        subtitle: String(localized: "Please try again later"),
        message: error
      )
      return
    }
    if secondsRemaining == 0 {
      secondsRemaining = UInt(AppConstants.Otp.defaultOtpExpirySeconds)
      currentStatus = .active
      updateRemainingTimeDisplay()
    }
    publishError(
      error.isEmpty ? String(localized: "Verification failed. Please try again.") : error)
  }
}
