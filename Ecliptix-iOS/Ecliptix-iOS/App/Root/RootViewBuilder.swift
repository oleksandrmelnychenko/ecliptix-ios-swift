// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

@MainActor
enum RootViewBuilder {

  @MainActor @ViewBuilder
  static func screenContent(coordinator: AppCoordinator, splashViewModel: SplashViewModel)
    -> some View
  {
    @Bindable var bindable = coordinator
    switch coordinator.currentScreen {
    case .splash:
      SplashView(viewModel: splashViewModel)
    case .welcome:
      WelcomeView(coordinator: coordinator)
    case .welcomeBack:
      WelcomeBackView(
        viewModel: coordinator.dependencies.makeWelcomeBackViewModel(
          onContinueToSetup: { [coordinator] membershipId, mobileNumber, membershipIdBytes in
            coordinator.presentPendingRegistration(
              .secureKey(
                membershipId: membershipId,
                mobileNumber: mobileNumber,
                membershipIdBytes: membershipIdBytes ?? membershipId.protobufBytes
              )
            )
          },
          onContinueLater: { [coordinator] in
            coordinator.navigateToWelcome()
          }
        )
      )
    case .signIn:
      NavigationStack(path: $bindable.navigationPath) {
        SignInView(
          viewModel: coordinator.cachedViewModel(key: "signIn") {
            makeSignInViewModel(coordinator: coordinator)
          },
          onBack: { [coordinator] in
            coordinator.navigateToWelcome()
          }
        )
        .navigationDestination(for: NavigationDestination.self) { destination in
          navigationDestination(for: destination, coordinator: coordinator)
        }
      }
    case .registration:
      NavigationStack(path: $bindable.navigationPath) {
        MobileVerificationView(
          viewModel: coordinator.cachedViewModel(key: "mobileVerification.registration") {
            makeMobileVerificationViewModel(coordinator: coordinator, context: .registration)
          },
          onBack: { [coordinator] in
            coordinator.navigateToWelcome()
          }
        )
        .navigationDestination(for: NavigationDestination.self) { destination in
          navigationDestination(for: destination, coordinator: coordinator)
        }
      }
    case .main:
      MainTabView(coordinator: coordinator, accountViewModel: coordinator.accountSettingsViewModel)
    case .error(let message):
      ErrorView(message: message, coordinator: coordinator)
    }
  }

  @MainActor @ViewBuilder
  private static func navigationDestination(
    for destination: NavigationDestination, coordinator: AppCoordinator
  ) -> some View {
    switch destination {
    case .mobileVerification(let context):
      MobileVerificationView(
        viewModel: coordinator.cachedViewModel(key: "mobileVerification.\(context)") {
          makeMobileVerificationViewModel(coordinator: coordinator, context: context)
        }
      )
    case .otpVerification(let sessionId, let mobileNumber, let context):
      OtpVerificationView(
        viewModel: coordinator.dependencies.makeOtpVerificationViewModel(
          sessionId: sessionId,
          mobileNumber: mobileNumber,
          flowContext: context,
          onVerificationSucceeded: { [coordinator] verification in
            coordinator.continueToSecureKey(
              sessionId: sessionId,
              mobileNumber: mobileNumber,
              context: context,
              membershipId: verification.membershipId.isZero ? nil : verification.membershipId,
              membershipIdBytes: verification.membershipIdBytes
            )
          },
          onAutoRedirect: { [coordinator] _ in
            if context == .signIn {
              coordinator.navigateToSignIn()
            } else {
              coordinator.navigateToWelcome()
            }
          }
        )
      )
    case .secureKeyConfirmation(
      let sessionId, let mobileNumber, let context, let membershipId, let membershipIdBytes):
      SecureKeyConfirmationView(
        viewModel: coordinator.dependencies.makeSecureKeyConfirmationViewModel(
          flowContext: context,
          mobileNumber: mobileNumber,
          membershipId: membershipId,
          membershipIdBytes: membershipIdBytes,
          onSecureKeyConfirmed: { [coordinator] in
            if context == .registration {
              coordinator.continueToPinSetup(
                sessionId: sessionId,
                mobileNumber: mobileNumber,
                context: .registration
              )
            } else {
              coordinator.navigateToSignIn()
            }
          }
        ),
        onBack: { [coordinator] in
          coordinator.popLast()
        }
      )
    case .completeProfile(let sessionId, let mobileNumber):
      CompleteProfileView(
        viewModel: coordinator.dependencies.makeCompleteProfileViewModel(
          sessionId: sessionId,
          mobileNumber: mobileNumber,
          onProfileCompleted: { [coordinator] in
            coordinator.completeRegistrationFromStoredState()
          }
        )
      )
    case .pinSetup(let sessionId, let mobileNumber, let context):
      PinSetupView(
        viewModel: coordinator.dependencies.makePinSetupViewModel(
          onPinSetupCompleted: { [coordinator] in
            switch context {
            case .registration:
              coordinator.continueToCompleteProfile(
                sessionId: sessionId,
                mobileNumber: mobileNumber
              )
            case .signIn:
              coordinator.completeSignInAfterPin()
            case .secureKeyRecovery:
              coordinator.navigateToSignIn()
            }
          }
        ),
        onBack: { [coordinator] in
          coordinator.popLast()
        }
      )
    case .pinEntry:
      PinEntryView(
        viewModel: coordinator.dependencies.makePinEntryViewModel(
          onPinVerified: { [coordinator] in
            coordinator.completeSignInAfterPin()
          }
        )
      )
    case .signIn:
      SignInView(
        viewModel: coordinator.cachedViewModel(key: "signIn") {
          makeSignInViewModel(coordinator: coordinator)
        },
        onBack: { [coordinator] in
          coordinator.navigateToWelcome()
        }
      )
    }
  }

  @MainActor
  private static func makeSignInViewModel(coordinator: AppCoordinator) -> SignInViewModel {
    coordinator.dependencies.makeSignInViewModel(
      onSignInInitiateSuccess: { [coordinator] _, _, creationStatus in
        coordinator.completeSignInFromStoredState(creationStatus: creationStatus)
      },
      onAccountRecovery: { [coordinator] in
        coordinator.startSecureKeyRecovery()
      },
      onAutoRedirectComplete: { [coordinator] in
        coordinator.navigateToWelcome()
      }
    )
  }

  @MainActor
  private static func makeMobileVerificationViewModel(
    coordinator: AppCoordinator,
    context: AuthenticationFlowContext
  ) -> MobileVerificationViewModel {
    coordinator.dependencies.makeMobileVerificationViewModel(
      flowContext: context,
      onMobileVerified: { [coordinator] route in
        handleMobileVerificationRoute(
          route,
          coordinator: coordinator,
          context: context
        )
      }
    )
  }

  @MainActor
  private static func handleMobileVerificationRoute(
    _ route: MobileVerificationRoute,
    coordinator: AppCoordinator,
    context: AuthenticationFlowContext
  ) {
    switch route {
    case .otp(let sessionId, let mobileNumber):
      coordinator.continueToOtpVerification(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context
      )
    case .secureKey(let sessionId, let mobileNumber, let membershipId):
      coordinator.continueToSecureKey(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context,
        membershipId: membershipId,
        membershipIdBytes: nil
      )
    case .pinSetup(let sessionId, let mobileNumber):
      coordinator.continueToPinSetup(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context
      )
    case .onboarding:
      coordinator.navigateToWelcome()
    }
  }
}
