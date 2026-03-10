// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

@Observable @MainActor
final class SignInViewModel: Resettable {

  var mobileNumber: String = "" {
    didSet {
      if hasServerError { clearServerError() }
      if !hasMobileNumberBeenTouched && !mobileNumber.isEmpty {
        hasMobileNumberBeenTouched = true
      }
      if hasMobileNumberBeenTouched {
        validateMobileNumber()
      }
    }
  }

  var secureKey: String = "" {
    didSet {
      if hasServerError { clearServerError() }
      if !hasSecureKeyBeenTouched && !secureKey.isEmpty {
        hasSecureKeyBeenTouched = true
      }
      if hasSecureKeyBeenTouched {
        validateSecureKey()
      }
    }
  }

  var mobileNumberError: String = ""
  var secureKeyError: String = ""
  var serverError: String = ""
  var serverFailureType: AuthenticationFailureType?
  var isBusy: Bool = false
  var countryFlag: String = "🇺🇸"
  var phonePrefix: String = "+1"
  var countryIso: String = "US"
  var selectedCountry: Country = .unitedStates {
    didSet {
      applyCountrySelection(selectedCountry, isManual: !isApplyingAutomaticCountrySelection)
    }
  }

  var showCountryPicker: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var isAutoRedirecting: Bool = false
  var autoRedirectTitle: String = ""
  var autoRedirectSubtitle: String = ""
  var autoRedirectCountdown: Int = 0
  var hasMobileNumberError: Bool { !mobileNumberError.isEmpty }
  var hasSecureKeyError: Bool { !secureKeyError.isEmpty }
  var hasServerError: Bool { !serverError.isEmpty }
  var userFacingServerError: String {
    guard let type = serverFailureType else { return serverError }
    switch type {
    case .invalidCredentials:
      return String(localized: "Incorrect mobile number or password")
    case .loginAttemptExceeded:
      return String(localized: "Too many failed attempts. Please try again later.")
    case .networkRequestFailed:
      return String(localized: "Connection error. Please check your internet and try again.")
    case .mobileNumberRequired:
      return String(localized: "Mobile number is required")
    case .secureKeyRequired:
      return String(localized: "Password is required")
    case .invalidMembershipId:
      return String(localized: "Account not found. Please check your details.")
    case .secureMemoryAllocationFailed, .secureMemoryWriteFailed,
      .keyDerivationFailed, .masterKeyDerivationFailed:
      return String(localized: "A security error occurred. Please restart the app and try again.")
    case .identityStorageFailed, .keychainCorrupted:
      return String(localized: "A storage error occurred. Please restart the app.")
    case .criticalAuthenticationError:
      return String(localized: "Authentication failed. Please try again.")
    case .registrationRequired:
      return String(localized: "Account not found. Please register first.")
    case .unexpectedError:
      return serverError.isEmpty
        ? String(localized: "Something went wrong. Please try again.")
        : ServerErrorMapper.userFacingMessage(serverError)
    }
  }

  var isSigningIn: Bool { isBusy }
  var phoneValidationError: String { mobileNumberError }
  var isFormValid: Bool { canSignIn }
  var canSignIn: Bool {
    !isBusy
      && mobileNumberError.isEmpty
      && secureKeyError.isEmpty
      && !mobileNumber.isEmpty
      && !secureKey.isEmpty
  }

  var hasMobileNumberBeenTouched: Bool = false
  var hasSecureKeyBeenTouched: Bool = false
  var hasManualCountrySelection: Bool = false
  var isApplyingAutomaticCountrySelection: Bool = false
  let autoRedirectTimer = CountdownTimer()
  private let opaqueAuthService: OpaqueAuthenticationService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let onSignInInitiateSuccess: (String, String, SignInCreationStatus) -> Void
  let onAccountRecovery: () -> Void
  let onAutoRedirectComplete: () -> Void

  init(
    opaqueAuthService: OpaqueAuthenticationService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    onSignInInitiateSuccess: @escaping (String, String, SignInCreationStatus) -> Void = { _, _, _ in
    },
    onAccountRecovery: @escaping () -> Void = {},
    onAutoRedirectComplete: @escaping () -> Void = {}
  ) {
    self.opaqueAuthService = opaqueAuthService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
    self.onSignInInitiateSuccess = onSignInInitiateSuccess
    self.onAccountRecovery = onAccountRecovery
    self.onAutoRedirectComplete = onAutoRedirectComplete
  }

  func accountRecovery() {
    onAccountRecovery()
  }

  func onAppear() {
    attemptAutoSwitchCountry()
  }

  func onDisappear() {
    autoRedirectTimer.cancel()
    isAutoRedirecting = false
    autoRedirectCountdown = 0
  }

  func signIn() async {
    validateForSubmit()
    guard canSignIn else { return }
    AppLogger.auth.debug("Sign-in submit tapped, mobileLength=\(self.mobileNumber.count)")
    clearServerError()
    isBusy = true
    let fullNumber = "\(phonePrefix)\(PhoneNumberValidator.cleanedNumber(mobileNumber))"
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    var secureKeyBytes = Data(secureKey.utf8)
    let secureKeyBuffer = SecureTextBuffer(consuming: &secureKeyBytes)
    OpaqueNative.secureZeroData(&secureKeyBytes)
    secureKey = ""
    defer { secureKeyBuffer.dispose() }

    let result = await opaqueAuthService.signIn(
      mobileNumber: fullNumber,
      secureKey: secureKeyBuffer,
      connectId: connectId
    )
    isBusy = false
    switch result {
    case .ok(let outcome):
      AppLogger.auth.info("Sign-in succeeded")
      serverError = ""
      onSignInInitiateSuccess("opaque-sign-in", fullNumber, outcome.creationStatus)
    case .err(let error):
      AppLogger.auth.error("Sign-in failed: \(error.message, privacy: .public)")
      handleSignInFailure(type: error.failureType, message: error.message)
    }
  }

  func clearError() {
    errorMessage = ""
    hasError = false
    clearServerError()
  }

  func setCountry(iso: String, prefix: String, flag: String) {
    selectedCountry =
      Country.fromRegionCode(iso)
      ?? Country(code: iso, name: iso.uppercased(), dialCode: prefix, flag: flag)
  }

  func cancelAutoRedirect() {
    autoRedirectTimer.cancel()
    isAutoRedirecting = false
    autoRedirectCountdown = 0
  }

  func resetState() {
    hasMobileNumberBeenTouched = false
    hasSecureKeyBeenTouched = false
    hasManualCountrySelection = false
    mobileNumber = ""
    secureKey = ""
    mobileNumberError = ""
    secureKeyError = ""
    serverError = ""
    serverFailureType = nil
    hasError = false
    errorMessage = ""
    showCountryPicker = false
    isAutoRedirecting = false
    autoRedirectTitle = ""
    autoRedirectSubtitle = ""
    autoRedirectCountdown = 0
    autoRedirectTimer.cancel()
    isApplyingAutomaticCountrySelection = true
    selectedCountry = .unitedStates
    isApplyingAutomaticCountrySelection = false
  }

  func validateMobileNumber() {
    mobileNumberError = PhoneNumberValidator.validate(mobileNumber) ?? ""
  }

  func validateSecureKey() {
    secureKeyError = secureKey.isEmpty ? String(localized: "Secure key is required") : ""
  }

  func validateForSubmit() {
    hasMobileNumberBeenTouched = true
    hasSecureKeyBeenTouched = true
    validateMobileNumber()
    validateSecureKey()
  }

  func clearServerError() {
    serverError = ""
    serverFailureType = nil
    errorMessage = ""
    hasError = false
  }

  func attemptAutoSwitchCountry() {
    guard !hasManualCountrySelection, mobileNumber.isEmpty else { return }
    if let regionCode = Locale.current.region?.identifier {
      let country =
        Country.fromRegionCode(regionCode)
        ?? Country(
          code: regionCode,
          name: regionCode,
          dialCode: "+1",
          flag: "🇺🇸"
        )
      isApplyingAutomaticCountrySelection = true
      selectedCountry = country
      isApplyingAutomaticCountrySelection = false
    }
  }

  func applyCountrySelection(_ country: Country, isManual: Bool) {
    if isManual { hasManualCountrySelection = true }
    countryIso = country.code
    phonePrefix = country.dialCode
    countryFlag = country.flag
  }
}
