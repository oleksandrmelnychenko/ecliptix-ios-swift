// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension MobileVerificationViewModel {

  func verifyMobileNumber() async {
    guard canVerify else { return }
    mobileNumberError = ""
    isBusy = true
    let fullNumber = "\(phonePrefix)\(PhoneNumberValidator.cleanedNumber(rawMobileNumber))"
    let result: Result<MobileVerificationRoute, String>
    if flowContext == .registration {
      guard let opaqueRegistrationService else {
        result = .err(String(localized: "Registration service is not configured"))
        isBusy = false
        errorMessage = result.err() ?? String(localized: "Unknown error")
        hasError = true
        return
      }

      let registrationResult = await opaqueRegistrationService.initiateRegistrationVerification(
        mobileNumber: fullNumber
      )
      switch registrationResult {
      case .ok(let response):
        switch response.nextStep {
        case .otp:
          result = .ok(.otp(sessionId: response.sessionId, mobileNumber: fullNumber))
        case .secureKey(let membershipId):
          result = .ok(
            .secureKey(
              sessionId: response.sessionId,
              mobileNumber: fullNumber,
              membershipId: membershipId
            )
          )
        case .pinSetup:
          result = .ok(.pinSetup(sessionId: response.sessionId, mobileNumber: fullNumber))
        case .onboarding:
          result = .err(String(localized: "This mobile number is already registered"))
        }
      case .err(let error):
        result = .err(error)
      }
    } else if flowContext == .secureKeyRecovery {
      let connectId = connectIdProvider(.dataCenterEphemeralConnect)
      let recoveryResult = await authService.initiateRecoveryVerification(
        mobileNumber: fullNumber,
        connectId: connectId
      )
      switch recoveryResult {
      case .ok(let response):
        result = .ok(.otp(sessionId: response.sessionId, mobileNumber: fullNumber))
      case .err(let rpcError):
        result = .err(rpcError.logDescription)
      }
    } else {
      let signInResult = await authService.signInInitiate(mobileNumber: fullNumber)
      switch signInResult {
      case .ok(let response):
        result = .ok(.otp(sessionId: response.sessionId, mobileNumber: fullNumber))
      case .err(let rpcError):
        result = .err(rpcError.logDescription)
      }
    }
    isBusy = false
    switch result {
    case .ok(let route):
      onMobileVerified(route)
    case .err(let error):
      let errLower = error.lowercased()
      if let normalizedKey = VerificationMessageKeys.normalizedKey(in: error),
        VerificationMessageKeys.isRateLimitKey(normalizedKey)
      {
        errorMessage = String(localized: "Too many attempts. Please try again later.")
        hasError = true
        return
      }
      if flowContext == .registration
        && (errLower.contains("already") || errLower.contains("registered"))
      {
        mobileNumberError = String(localized: "This mobile number is already registered")
      } else if (flowContext == .secureKeyRecovery || flowContext == .signIn)
        && (errLower.contains("not found") || errLower.contains("no account"))
      {
        mobileNumberError = String(localized: "No account found with this mobile number")
      } else {
        errorMessage = ServerErrorMapper.userFacingMessage(error)
        hasError = true
      }
    }
  }
}
