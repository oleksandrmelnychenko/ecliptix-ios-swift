// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

enum PendingRegistrationRoute: Equatable {
  case start
  case secureKey(membershipId: UUID, mobileNumber: String, membershipIdBytes: Data)
  case pinSetup(mobileNumber: String)
  case completeProfile(mobileNumber: String)
}

enum StartupFlowDecision: Equatable {
  case welcome
  case main(accountId: UUID, membershipId: UUID)
  case pendingRegistration(PendingRegistrationRoute)
  case error(message: String)
}

enum StoredSignInDecision: Equatable {
  case signIn
  case pinEntry
  case pinSetup
}

enum StoredRegistrationDecision: Equatable {
  case main(accountId: UUID, membershipId: UUID)
  case pendingRegistration(PendingRegistrationRoute)
}

final class AppFlowResolver {

  func resolveStartupDecision(
    initializationResult: ApplicationInitializationResult,
    applicationState: ApplicationState,
    settings: ApplicationInstanceSettings?,
    storedIdentity: (accountId: UUID, membershipId: UUID)?
  ) -> StartupFlowDecision {
    switch initializationResult {
    case .success:
      if let pendingRoute = resolvePendingRegistrationRoute(
        settings: settings,
        isAuthenticated: applicationState == .authenticated
      ) {
        return .pendingRegistration(pendingRoute)
      }

      if applicationState == .authenticated,
        let storedIdentity
      {
        return .main(
          accountId: storedIdentity.accountId,
          membershipId: storedIdentity.membershipId
        )
      }

      return .welcome

    case .settingsInitializationFailed(let details):
      return .error(
        message: startupErrorMessage(
          details: details,
          fallback: AppErrorMessages.startupGenericIssue
        )
      )

    case .secrecyChannelFailed(let details):
      if NetworkErrorClassifier.isConnectivityIssue(details) {
        AppLogger.app.warning(
          "Startup: secrecy channel unavailable, continuing to welcome. details=\(details, privacy: .public)"
        )
        return .welcome
      }

      return .error(
        message: startupErrorMessage(
          details: details,
          fallback: AppErrorMessages.startupConnectionIssue
        )
      )

    case .deviceRegistrationFailed(let details):
      if NetworkErrorClassifier.isConnectivityIssue(details) {
        AppLogger.app.warning(
          "Startup: device registration unavailable, continuing to welcome. details=\(details, privacy: .public)"
        )
        return .welcome
      }

      return .error(
        message: startupErrorMessage(
          details: details,
          fallback: AppErrorMessages.startupConnectionIssue
        )
      )
    }
  }

  func resolveStoredSignInDecision(
    creationStatus: SignInCreationStatus,
    storedIdentity: (accountId: UUID, membershipId: UUID)?
  ) -> StoredSignInDecision {
    guard storedIdentity != nil else {
      return .signIn
    }

    switch creationStatus {
    case .secureKeySet:
      return .pinSetup
    case .passphraseSet:
      return .pinEntry
    }
  }

  func resolveStoredRegistrationDecision(
    settings: ApplicationInstanceSettings?,
    storedIdentity: (accountId: UUID, membershipId: UUID)?
  ) -> StoredRegistrationDecision {
    if let storedIdentity {
      return .main(
        accountId: storedIdentity.accountId,
        membershipId: storedIdentity.membershipId
      )
    }

    if let pendingRoute = resolvePendingRegistrationRoute(
      settings: settings,
      isAuthenticated: false
    ) {
      return .pendingRegistration(pendingRoute)
    }

    return .pendingRegistration(.start)
  }

  private func startupErrorMessage(details: String, fallback: String) -> String {
    if NetworkErrorClassifier.isConnectivityIssue(details) {
      return AppErrorMessages.startupConnectionIssue
    }

    return fallback
  }

  private func resolvePendingRegistrationRoute(
    settings: ApplicationInstanceSettings?,
    isAuthenticated: Bool
  ) -> PendingRegistrationRoute? {
    guard let settings,
      let membership = settings.membership,
      !membership.membershipId.isZero
    else {
      return nil
    }

    let secureKeyRoute = PendingRegistrationRoute.secureKey(
      membershipId: membership.membershipId,
      mobileNumber: membership.mobileNumber,
      membershipIdBytes: membership.membershipId.protobufBytes
    )

    if let checkpoint = settings.registrationCheckpoint {
      switch checkpoint {
      case .otpVerified:
        return secureKeyRoute

      case .secureKeySet:
        guard settings.currentAccountId != nil else {
          return secureKeyRoute
        }
        return .pinSetup(mobileNumber: membership.mobileNumber)

      case .pinSet:
        guard settings.currentAccountId != nil else {
          return secureKeyRoute
        }
        return .completeProfile(mobileNumber: membership.mobileNumber)

      case .profileCompleted:
        return nil
      }
    }

    if !isAuthenticated && settings.currentAccountId == nil {
      return secureKeyRoute
    }

    return nil
  }
}
