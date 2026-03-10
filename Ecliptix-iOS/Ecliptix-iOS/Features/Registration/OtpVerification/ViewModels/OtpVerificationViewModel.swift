import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

enum OtpCountdownStatus: String {
  case active = "ACTIVE"
  case expired = "EXPIRED"
  case resendCooldown = "RESEND_COOLDOWN"
  case failed = "FAILED"
  case notFound = "NOT_FOUND"
  case maxAttemptsReached = "MAX_ATTEMPTS_REACHED"
  case sessionExpired = "SESSION_EXPIRED"
  case serverUnavailable = "SERVER_UNAVAILABLE"
}

enum OtpCountdownViewStatus {
  case active(Int)
  case expired
  case resendCooldown(Int)
  case failed
  case notFound
  case maxAttemptsReached
  case sessionExpired
  case serverUnavailable
}

@Observable @MainActor
final class OtpVerificationViewModel {

  var verificationCode: String = "" {
    didSet {
      if hasError { publishError("") }
      syncOtpDigitsFromVerificationCode()
    }
  }

  var otpDigits: [String] = Array(repeating: "", count: AppConstants.Otp.defaultOtpCodeLength)
  var errorMessage: String = ""
  var remainingTime: String = String(
    format: "%02d:%02d",
    AppConstants.Otp.defaultOtpExpirySeconds / 60,
    AppConstants.Otp.defaultOtpExpirySeconds % 60
  )
  var hasError: Bool = false
  var isBusy: Bool = false
  var isResending: Bool = false
  var hasValidSession: Bool = false
  var isMaxAttemptsReached: Bool = false
  var resendSucceeded: Bool = false
  var isAutoRedirecting: Bool = false
  var autoRedirectTitle: String = ""
  var autoRedirectSubtitle: String = ""
  var autoRedirectCountdown: Int = 0
  var secondsRemaining: UInt = 0
  var cooldownBufferSeconds: UInt = 0
  var currentStatus: OtpCountdownStatus = .active
  var verificationSessionId: String?
  private(set) var countdownTask: Task<Void, Never>?
  private(set) var cooldownTask: Task<Void, Never>?
  let autoRedirectTimer = CountdownTimer()
  private(set) var otpStreamTask: Task<Void, Never>?
  var otpStreamCancellationToken: CancellationToken = CancellationToken()
  var alreadyVerifiedHandled: Bool = false
  private var otpStreamConnectId: UInt32?
  var originalMobileNumberSessionId: String?
  private(set) var isOtpVerificationInProgress: Bool = false
  private var countdownVersion: Int64 = 0
  private var autoRedirectVersion: Int64 = 0
  let authService: AuthenticationRpcService
  let secureStorageService: SecureStorageService
  let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let mobileNumber: String
  let flowContext: AuthenticationFlowContext
  let onVerificationSucceeded: (OtpVerificationResult) -> Void
  let onAutoRedirect: (OtpCountdownStatus) -> Void
  var userFacingError: String {
    guard hasError else { return "" }
    return ServerErrorMapper.userFacingMessage(errorMessage)
  }

  var isTerminalStatus: Bool {
    switch currentStatus {
    case .notFound, .maxAttemptsReached, .sessionExpired, .serverUnavailable, .failed:
      return true
    case .active, .expired, .resendCooldown:
      return false
    }
  }

  var canVerify: Bool {
    !verificationCode.isEmpty && verificationCode.count == AppConstants.Otp.defaultOtpCodeLength
      && verificationCode.allSatisfy({ $0.isNumber }) && !isTerminalStatus
      && currentStatus != .expired && !isBusy
      && !isOtpVerificationInProgress && !alreadyVerifiedHandled
  }

  var canResend: Bool {
    hasValidSession && !isResending && secondsRemaining == 0
      && currentStatus == .expired && cooldownBufferSeconds == 0
  }

  var countdownStatus: OtpCountdownViewStatus {
    switch currentStatus {
    case .active: return .active(Int(secondsRemaining))
    case .expired: return .expired
    case .resendCooldown: return .resendCooldown(Int(cooldownBufferSeconds))
    case .failed: return .failed
    case .notFound: return .notFound
    case .maxAttemptsReached: return .maxAttemptsReached
    case .sessionExpired: return .sessionExpired
    case .serverUnavailable: return .serverUnavailable
    }
  }

  init(
    mobileNumber: String,
    flowContext: AuthenticationFlowContext = .registration,
    authService: AuthenticationRpcService,
    secureStorageService: SecureStorageService,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    sessionId: String? = nil,
    onVerificationSucceeded: @escaping (OtpVerificationResult) -> Void = { _ in },
    onAutoRedirect: @escaping (OtpCountdownStatus) -> Void = { _ in }
  ) {
    self.mobileNumber = mobileNumber
    self.flowContext = flowContext
    self.authService = authService
    self.secureStorageService = secureStorageService
    self.connectIdProvider = connectIdProvider
    self.onVerificationSucceeded = onVerificationSucceeded
    self.onAutoRedirect = onAutoRedirect
    if let sessionId, !sessionId.isEmpty {
      verificationSessionId = sessionId
      originalMobileNumberSessionId = sessionId
      hasValidSession = true
      secondsRemaining = UInt(AppConstants.Otp.defaultOtpExpirySeconds)
      currentStatus = .active
      updateRemainingTimeDisplay()
    }
  }

  func onAppear() async {
    if hasValidSession {
      secondsRemaining = UInt(AppConstants.Otp.defaultOtpExpirySeconds)
      currentStatus = .active
      updateRemainingTimeDisplay()
    }

    let version = startNewCountdownVersion()
    AppLogger.auth.info(
      "OTP VM: onAppear start stream context=\(String(describing: self.flowContext), privacy: .public), version=\(version, privacy: .public)"
    )
    await initiateOtpSession(
      countdownVersion: version, requestTypeRawValue: AppConstants.Otp.requestTypeSend)
  }

  func startCountdown() {
    if hasValidSession {
      let version = startNewCountdownVersion()
      if secondsRemaining == 0 {
        secondsRemaining = UInt(AppConstants.Otp.defaultOtpExpirySeconds)
        currentStatus = .active
        updateRemainingTimeDisplay()
      }
      startCountdownTask(version: version)
      replaceOtpStreamTask(with: Task { [weak self] in
        await self?.initiateOtpSession(
          countdownVersion: version,
          requestTypeRawValue: AppConstants.Otp.requestTypeSend
        )
      })
      return
    }
    replaceOtpStreamTask(with: Task { [weak self] in
      await self?.onAppear()
    })
  }

  func onDisappear() {
    cancelAllTasks()
    isAutoRedirecting = false
    cleanupSession()
  }

  func verifyOtp() async {
    guard canVerify else {
      if currentStatus == .expired {
        publishError(String(localized: "Code expired. Please request a new one."))
      }
      return
    }
    errorMessage = ""
    hasError = false
    guard hasValidSession, let sessionId = verificationSessionId else {
      publishError(String(localized: "No verification session available"))
      return
    }
    isOtpVerificationInProgress = true
    isBusy = true
    defer {
      isOtpVerificationInProgress = false
      isBusy = false
    }

    let result = await authService.verifyOtp(
      verificationId: sessionId,
      otpCode: verificationCode,
      purposeRawValue: otpPurposeRawValue(),
      streamConnectId: resolveOtpConnectId(),
      connectId: currentConnectId()
    )
    switch result {
    case .ok(let verification):
      AppLogger.auth.info(
        "OTP VM: verify success context=\(String(describing: self.flowContext), privacy: .public), membership=\(verification.membershipId.uuidString, privacy: .public)"
      )
      await handleSuccessfulVerification(verification)
    case .err(let rpcError):
      AppLogger.auth.warning(
        "OTP VM: verify failed context=\(String(describing: self.flowContext), privacy: .public), error=\(rpcError.logDescription, privacy: .public)"
      )
      publishError(rpcError.userFacingMessage)
    }
  }

  func resendOtp() async {
    guard canResend else {
      if !hasValidSession { publishError(String(localized: "No active verification session")) }
      AppLogger.auth.warning(
        "OTP VM: resendOtp guard failed hasValidSession=\(self.hasValidSession, privacy: .public), isResending=\(self.isResending, privacy: .public), status=\(self.currentStatus.rawValue, privacy: .public)"
      )
      return
    }
    guard let sessionId = originalMobileNumberSessionId ?? verificationSessionId, !sessionId.isEmpty
    else {
      publishError(String(localized: "No active verification session"))
      AppLogger.auth.warning("OTP VM: resendOtp no sessionId")
      return
    }
    errorMessage = ""
    hasError = false
    isResending = true
    verificationCode = ""
    let oldStreamTask = otpStreamTask
    clearOtpStreamTask()
    otpStreamCancellationToken.cancel()
    otpStreamCancellationToken = CancellationToken()
    oldStreamTask?.cancel()
    await oldStreamTask?.value
    let version = startNewCountdownVersion()
    secondsRemaining = UInt(AppConstants.Otp.defaultOtpExpirySeconds)
    currentStatus = .active
    updateRemainingTimeDisplay()
    let connectId = resolveOtpConnectId()
    let cancellationToken = otpStreamCancellationToken
    AppLogger.auth.info(
      "OTP VM: resendOtp start version=\(version, privacy: .public), connectId=\(connectId, privacy: .public), sessionId=\(sessionId, privacy: .private(mask: .hash))"
    )
    let result = await authService.startOtpCountdownStream(
      sessionId: sessionId,
      purposeRawValue: otpPurposeRawValue(),
      requestTypeRawValue: AppConstants.Otp.requestTypeResend,
      connectId: connectId,
      onUpdate: { [weak self] update in
        Task { @MainActor [weak self] in
          self?.handleCountdownUpdate(update, version: version)
        }
      },
      cancellationToken: cancellationToken
    )
    isResending = false
    AppLogger.auth.info(
      "OTP VM: resendOtp stream ended isOk=\(result.isOk, privacy: .public)"
    )
    switch result {
    case .ok:
      // Ensure countdown is running even if stream closed before callback was processed
      if currentStatus == .active && secondsRemaining > 0 {
        startCountdownTask(version: version)
        showResendSuccess()
      }
    case .err(let rpcError):
      handleResendError(rpcError.logDescription)
      // If the stream update already set active countdown, show success
      if currentStatus == .active && secondsRemaining > 0 {
        showResendSuccess()
      }
    }
  }

  private var resendDismissTask: Task<Void, Never>?

  func showResendSuccess() {
    resendSucceeded = true
    resendDismissTask?.cancel()
    resendDismissTask = Task { @MainActor [weak self] in
      try? await Task.sleep(nanoseconds: 3_000_000_000)
      guard !Task.isCancelled else { return }
      self?.resendSucceeded = false
    }
  }

  func publishError(_ message: String) {
    errorMessage = message
    hasError = !message.isEmpty
  }

  func cleanupSession() {
    guard let sessionId = verificationSessionId, !sessionId.isEmpty else { return }
    authService.closeVerificationStream(sessionId)
  }

  func cancelAllTasks() {
    otpStreamConnectId = nil
    clearCountdownTask()
    clearCooldownTask()
    resendDismissTask?.cancel()
    resendDismissTask = nil
    autoRedirectTimer.cancel()
    clearOtpStreamTask()
    otpStreamCancellationToken.cancel()
  }

  func replaceCountdownTask(with task: Task<Void, Never>?) {
    countdownTask?.cancel()
    countdownTask = task
  }

  func clearCountdownTask() {
    countdownTask?.cancel()
    countdownTask = nil
  }

  func replaceCooldownTask(with task: Task<Void, Never>?) {
    cooldownTask?.cancel()
    cooldownTask = task
  }

  func clearCooldownTask() {
    cooldownTask?.cancel()
    cooldownTask = nil
  }

  func replaceOtpStreamTask(with task: Task<Void, Never>?) {
    otpStreamTask?.cancel()
    otpStreamTask = task
  }

  func clearOtpStreamTask() {
    otpStreamTask?.cancel()
    otpStreamTask = nil
  }

  func syncOtpDigitsFromVerificationCode() {
    let trimmed = String(verificationCode.prefix(AppConstants.Otp.defaultOtpCodeLength))
    if trimmed != verificationCode {
      verificationCode = trimmed
      return
    }

    var digits = Array(trimmed).map(String.init)
    while digits.count < 6 { digits.append("") }
    if digits != otpDigits { otpDigits = digits }
  }

  func startNewCountdownVersion() -> Int64 {
    alreadyVerifiedHandled = false
    autoRedirectVersion = 0
    countdownVersion += 1
    return countdownVersion
  }

  func invalidateCountdown() {
    countdownVersion += 1
  }

  func isCountdownVersionCurrent(_ version: Int64) -> Bool {
    version == countdownVersion
  }

  func tryStartAutoRedirectOnce() -> Bool {
    guard autoRedirectVersion == 0 else { return false }
    autoRedirectVersion += 1
    return true
  }

  func containsCaseInsensitive(_ source: String, _ substring: String) -> Bool {
    source.range(of: substring, options: .caseInsensitive) != nil
  }

  func isServerUnavailableError(_ error: String) -> Bool {
    NetworkErrorClassifier.isConnectivityIssue(error)
  }

  func otpPurposeRawValue() -> Int {
    switch flowContext {
    case .registration: return AppConstants.Otp.purposeRegistration
    case .signIn: return AppConstants.Otp.purposeSignIn
    case .secureKeyRecovery: return AppConstants.Otp.purposePasswordRecovery
    }
  }

  func currentConnectId() -> UInt32 {
    connectIdProvider(.dataCenterEphemeralConnect)
  }

  func resolveOtpConnectId() -> UInt32 {
    if let otpStreamConnectId {
      return otpStreamConnectId
    }

    let connectId = connectIdProvider(.serverStreaming)
    otpStreamConnectId = connectId
    return connectId
  }
}
