// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension AppDependencies {

  @MainActor
  func makeSignInViewModel(
    onSignInInitiateSuccess: @escaping (String, String, SignInCreationStatus) -> Void = { _, _, _ in
    },
    onAccountRecovery: @escaping () -> Void = {},
    onAutoRedirectComplete: @escaping () -> Void = {}
  ) -> SignInViewModel {
    SignInViewModel(
      opaqueAuthService: opaqueAuthenticationService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider(),
      onSignInInitiateSuccess: onSignInInitiateSuccess,
      onAccountRecovery: onAccountRecovery,
      onAutoRedirectComplete: onAutoRedirectComplete
    )
  }

  @MainActor
  func makeOtpVerificationViewModel(
    sessionId: String,
    mobileNumber: String,
    flowContext: AuthenticationFlowContext = .registration,
    onVerificationSucceeded: @escaping (OtpVerificationResult) -> Void = { _ in },
    onAutoRedirect: @escaping (OtpCountdownStatus) -> Void = { _ in }
  ) -> OtpVerificationViewModel {
    OtpVerificationViewModel(
      mobileNumber: mobileNumber,
      flowContext: flowContext,
      authService: authenticationRpcService,
      secureStorageService: secureStorageService,
      connectIdProvider: weakConnectIdProvider(),
      sessionId: sessionId,
      onVerificationSucceeded: onVerificationSucceeded,
      onAutoRedirect: onAutoRedirect
    )
  }

  @MainActor
  func makeMobileVerificationViewModel(
    flowContext: AuthenticationFlowContext = .registration,
    onMobileVerified: @escaping (MobileVerificationRoute) -> Void = { _ in }
  ) -> MobileVerificationViewModel {
    MobileVerificationViewModel(
      authService: authenticationRpcService,
      opaqueRegistrationService: opaqueRegistrationService,
      connectIdProvider: weakConnectIdProvider(),
      flowContext: flowContext,
      onMobileVerified: onMobileVerified
    )
  }

  @MainActor
  func makeSecureKeyConfirmationViewModel(
    flowContext: AuthenticationFlowContext = .registration,
    mobileNumber: String = "",
    membershipId: UUID? = nil,
    membershipIdBytes: Data? = nil,
    onSecureKeyConfirmed: @escaping () -> Void = {}
  ) -> SecureKeyConfirmationViewModel {
    SecureKeyConfirmationViewModel(
      flowContext: flowContext,
      authService: authenticationRpcService,
      opaqueAuthService: opaqueAuthenticationService,
      opaqueRegistrationService: opaqueRegistrationService,
      secureKeyRecoveryService: secureKeyRecoveryService,
      mobileNumber: mobileNumber,
      membershipId: membershipId,
      membershipIdBytes: membershipIdBytes,
      localization: LocalizationService.shared,
      connectIdProvider: weakConnectIdProvider(),
      onSecureKeyConfirmed: onSecureKeyConfirmed
    )
  }

  @MainActor
  func makeCompleteProfileViewModel(
    sessionId: String,
    mobileNumber: String,
    onProfileCompleted: @escaping () -> Void = {}
  ) -> CompleteProfileViewModel {
    CompleteProfileViewModel(
      profileService: profileRpcService,
      secureStorageService: secureStorageService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider(),
      sessionId: sessionId,
      mobileNumber: mobileNumber,
      onProfileCompleted: onProfileCompleted
    )
  }

  @MainActor
  func makePinSetupViewModel(
    onPinSetupCompleted: @escaping () -> Void = {}
  ) -> PinSetupViewModel {
    PinSetupViewModel(
      pinOpaqueService: pinOpaqueService,
      secureStorageService: secureStorageService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider(),
      onPinSetupCompleted: onPinSetupCompleted
    )
  }

  @MainActor
  func makePinEntryViewModel(
    onPinVerified: @escaping () -> Void = {}
  ) -> PinEntryViewModel {
    PinEntryViewModel(
      pinOpaqueService: pinOpaqueService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider(),
      onPinVerified: onPinVerified
    )
  }

  @MainActor
  func makeWelcomeBackViewModel(
    onContinueToSetup: @escaping (UUID, String, Data?) -> Void = { _, _, _ in },
    onContinueLater: @escaping () -> Void = {}
  ) -> WelcomeBackViewModel {
    WelcomeBackViewModel(
      settingsProvider: weakSettingsProvider(),
      onContinueToSetup: onContinueToSetup,
      onContinueLater: onContinueLater
    )
  }
}
