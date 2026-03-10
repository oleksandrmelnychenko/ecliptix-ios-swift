// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum MobileVerificationRoute {
  case otp(sessionId: String, mobileNumber: String)
  case secureKey(sessionId: String, mobileNumber: String, membershipId: UUID?)
  case pinSetup(sessionId: String, mobileNumber: String)
  case onboarding
}

@Observable @MainActor
final class MobileVerificationViewModel: Resettable {

  var rawMobileNumber: String = "" {
    didSet {
      if hasError { clearServerError() }
      if !hasMobileNumberBeenTouched && !rawMobileNumber.isEmpty {
        hasMobileNumberBeenTouched = true
      }
      if hasMobileNumberBeenTouched {
        validateMobileNumber()
      }
    }
  }

  var mobileNumberError: String = ""
  var isBusy: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var showCountryPicker: Bool = false
  var hasAgreedToTerms: Bool = false {
    didSet {
      guard hasAgreedToTerms else { return }
      if !termsValidationError.isEmpty {
        termsValidationError = ""
      }
      if hasError && errorMessage == termsRequiredMessage {
        clearServerError()
      }
    }
  }

  var termsValidationError: String = ""
  var countryFlag: String = "🇺🇸"
  var phonePrefix: String = "+1"
  var countryIso: String = "US"
  var selectedCountry: Country = .unitedStates {
    didSet {
      applySelectedCountry(selectedCountry)
      hasManualCountrySelection = true
    }
  }

  var hasMobileNumberError: Bool { !mobileNumberError.isEmpty }
  private var termsRequiredMessage: String {
    String(localized: "Please accept Terms of Service and Privacy Policy")
  }

  var userFacingError: String {
    guard hasError else { return "" }
    return ServerErrorMapper.userFacingMessage(errorMessage)
  }

  var hasMobileNumberBeenTouched: Bool = false
  var hasManualCountrySelection: Bool = false
  let flowContext: AuthenticationFlowContext
  let authService: AuthenticationRpcService
  let opaqueRegistrationService: OpaqueRegistrationService?
  let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let onMobileVerified: (MobileVerificationRoute) -> Void
  var mobileNumber: String {
    get { rawMobileNumber }
    set { rawMobileNumber = newValue }
  }

  var phoneValidationError: String { mobileNumberError }
  var canVerify: Bool { !isBusy && mobileNumberError.isEmpty && !rawMobileNumber.isEmpty }
  var isSendingCode: Bool { isBusy }
  var isFormValid: Bool {
    flowContext == .registration
      ? canVerify && hasAgreedToTerms && termsValidationError.isEmpty : canVerify
  }

  var title: String {
    switch flowContext {
    case .registration: return String(localized: "Create Account")
    case .secureKeyRecovery: return String(localized: "Recover Secure Key")
    case .signIn: return String(localized: "Sign In")
    }
  }

  var description: String {
    switch flowContext {
    case .registration: return String(localized: "Enter your mobile number to get started")
    case .secureKeyRecovery:
      return String(localized: "Enter your mobile number to recover your secure key")
    case .signIn: return String(localized: "Enter your mobile number to sign in")
    }
  }

  var subtitle: String { description }
  var infoMessage: String {
    switch flowContext {
    case .registration: return String(localized: "We will send a verification code to this number")
    case .secureKeyRecovery:
      return String(localized: "Use your registered number to recover access")
    case .signIn: return String(localized: "Use your account number to continue sign in")
    }
  }

  var buttonText: String {
    switch flowContext {
    case .registration: return String(localized: "Continue")
    case .secureKeyRecovery: return String(localized: "Recover Key")
    case .signIn: return String(localized: "Sign In")
    }
  }

  var stepBadgeText: String {
    switch flowContext {
    case .registration: return String(localized: "Step 1 of 6")
    case .secureKeyRecovery: return String(localized: "Step 1 of 3")
    case .signIn: return ""
    }
  }

  init(
    authService: AuthenticationRpcService,
    opaqueRegistrationService: OpaqueRegistrationService? = nil,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    flowContext: AuthenticationFlowContext,
    onMobileVerified: @escaping (MobileVerificationRoute) -> Void = { _ in }
  ) {
    self.flowContext = flowContext
    self.authService = authService
    self.opaqueRegistrationService = opaqueRegistrationService
    self.connectIdProvider = connectIdProvider
    self.onMobileVerified = onMobileVerified
  }

  func onAppear() {
    attemptAutoSwitchCountry()
  }

  func sendVerificationCode() async {
    if flowContext == .registration && !hasAgreedToTerms {
      termsValidationError = termsRequiredMessage
      hasError = true
      errorMessage = termsValidationError
      return
    }
    termsValidationError = ""
    hasError = false
    errorMessage = ""
    await verifyMobileNumber()
  }

  func setCountry(iso: String, prefix: String, flag: String) {
    hasManualCountrySelection = true
    selectedCountry =
      Country.fromRegionCode(iso)
      ?? Country(code: iso, name: iso.uppercased(), dialCode: prefix, flag: flag)
    applySelectedCountry(selectedCountry)
  }

  func resetState() {
    hasMobileNumberBeenTouched = false
    hasManualCountrySelection = false
    rawMobileNumber = ""
    mobileNumberError = ""
    hasError = false
    errorMessage = ""
    hasAgreedToTerms = false
    termsValidationError = ""
    showCountryPicker = false
    selectedCountry = .unitedStates
    applySelectedCountry(selectedCountry)
    hasManualCountrySelection = false
  }

  func clearServerError() {
    hasError = false
    errorMessage = ""
  }

  func validateMobileNumber() {
    mobileNumberError = PhoneNumberValidator.validate(rawMobileNumber) ?? ""
  }

  func attemptAutoSwitchCountry() {
    guard !hasManualCountrySelection, rawMobileNumber.isEmpty else { return }
    if let regionCode = Locale.current.region?.identifier,
      let country = Country.fromRegionCode(regionCode)
    {
      selectedCountry = country
      applySelectedCountry(country)
      hasManualCountrySelection = false
    }
  }

  func applySelectedCountry(_ country: Country) {
    countryIso = country.code
    phonePrefix = country.dialCode
    countryFlag = country.flag
  }
}
