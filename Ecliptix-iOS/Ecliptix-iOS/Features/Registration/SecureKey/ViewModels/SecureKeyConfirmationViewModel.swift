// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct RequirementItem: Identifiable {

  let id: String
  let description: String
  let isSatisfied: Bool

  init(id: String? = nil, description: String, isSatisfied: Bool) {
    self.id = id ?? description
    self.description = description
    self.isSatisfied = isSatisfied
  }
}

@Observable @MainActor
final class SecureKeyConfirmationViewModel: Resettable {

  var secureKey: String = "" {
    didSet {
      if !hasSecureKeyBeenTouched && !secureKey.isEmpty {
        hasSecureKeyBeenTouched = true
      }
      if hasSecureKeyBeenTouched {
        validateSecureKey()
      }
      if hasVerifySecureKeyBeenTouched {
        validateVerifySecureKey()
      }
    }
  }

  var verifySecureKey: String = "" {
    didSet {
      if !hasVerifySecureKeyBeenTouched && !verifySecureKey.isEmpty {
        hasVerifySecureKeyBeenTouched = true
      }
      if hasVerifySecureKeyBeenTouched {
        validateVerifySecureKey()
      }
    }
  }

  var secureKeyError: String = ""
  var verifySecureKeyError: String = ""
  var serverError: String = ""
  var isBusy: Bool = false
  var validationTips: [RequirementItem] = []
  var recommendations: [String] = []
  var isSecureKeySuccess: Bool = false
  var currentSecureKeyStrength: SecureKeyStrength = .invalid
  var secureKeyStrengthMessage: String = ""
  var hasSecureKeyBeenTouched: Bool = false
  var hasSecureKeyError: Bool { !secureKeyError.isEmpty }
  var hasVerifySecureKeyError: Bool { !verifySecureKeyError.isEmpty }
  var hasServerError: Bool { !serverError.isEmpty }
  var hasVerifySecureKeyBeenTouched: Bool = false
  let localization: any LocalizationProviding
  let flowContext: AuthenticationFlowContext
  let authService: AuthenticationRpcService
  let opaqueAuthService: OpaqueAuthenticationService?
  let opaqueRegistrationService: OpaqueRegistrationService?
  let secureKeyRecoveryService: SecureKeyRecoveryService?
  let mobileNumber: String?
  let membershipId: UUID?
  let membershipIdBytes: Data?
  let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let onSecureKeyConfirmed: () -> Void
  var canSubmit: Bool {
    !isBusy && secureKeyError.isEmpty && verifySecureKeyError.isEmpty
      && !secureKey.isEmpty && !verifySecureKey.isEmpty
      && SecureKeyValidator.constantTimeEquals(secureKey, verifySecureKey)
      && isSecureKeySuccess
  }

  var title: String {
    switch flowContext {
    case .registration: return String(localized: "Create Secure Key")
    case .secureKeyRecovery: return String(localized: "Reset Secure Key")
    case .signIn: return String(localized: "Secure Key")
    }
  }

  var description: String {
    switch flowContext {
    case .registration:
      return String(localized: "Create a strong secure key to protect your account")
    case .secureKeyRecovery: return String(localized: "Create a new secure key for your account")
    case .signIn: return String(localized: "Enter your secure key")
    }
  }

  var buttonText: String {
    switch flowContext {
    case .registration: return String(localized: "Continue")
    case .secureKeyRecovery: return String(localized: "Reset Key")
    case .signIn: return String(localized: "Sign In")
    }
  }

  var stepBadgeText: String {
    switch flowContext {
    case .registration: return String(localized: "Step 3 of 6")
    case .secureKeyRecovery: return String(localized: "Step 3 of 3")
    case .signIn: return ""
    }
  }

  var requirementsTitle: String {
    isSecureKeySuccess ? String(localized: "Requirements Met") : String(localized: "Requirements")
  }

  init(
    flowContext: AuthenticationFlowContext,
    authService: AuthenticationRpcService,
    opaqueAuthService: OpaqueAuthenticationService? = nil,
    opaqueRegistrationService: OpaqueRegistrationService? = nil,
    secureKeyRecoveryService: SecureKeyRecoveryService? = nil,
    mobileNumber: String? = nil,
    membershipId: UUID? = nil,
    membershipIdBytes: Data? = nil,
    localization: any LocalizationProviding,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    onSecureKeyConfirmed: @escaping () -> Void = {}
  ) {
    self.flowContext = flowContext
    self.authService = authService
    self.opaqueAuthService = opaqueAuthService
    self.opaqueRegistrationService = opaqueRegistrationService
    self.secureKeyRecoveryService = secureKeyRecoveryService
    self.mobileNumber = mobileNumber
    self.membershipId = membershipId
    self.membershipIdBytes = membershipIdBytes
    self.localization = localization
    self.connectIdProvider = connectIdProvider
    self.onSecureKeyConfirmed = onSecureKeyConfirmed
    initializeValidationTips()
  }

  func onAppear() {}

  func resetState() {
    secureKey = ""
    verifySecureKey = ""
    secureKeyError = ""
    verifySecureKeyError = ""
    serverError = ""
    hasSecureKeyBeenTouched = false
    hasVerifySecureKeyBeenTouched = false
    isSecureKeySuccess = false
    currentSecureKeyStrength = .invalid
    secureKeyStrengthMessage = ""
    recommendations = []
    initializeValidationTips()
  }
}
