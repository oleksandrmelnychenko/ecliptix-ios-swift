// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@MainActor
extension AppCoordinator {

  func applyStartupDecision(_ decision: StartupFlowDecision) {
    switch decision {
    case .welcome:
      navigateToWelcome(clearStartupNotice: startupNotice == nil)
    case .main(let accountId, let membershipId):
      navigateToMain(accountId: accountId, membershipId: membershipId)
    case .pendingRegistration(let route):
      presentPendingRegistration(route)
    case .error(let message):
      currentScreen = .error(message: message)
    }
  }

  func navigateToSignIn() {
    startupNotice = nil
    currentScreen = .signIn
    navigationPath.removeAll()
  }

  func navigateToRegistration() {
    startupNotice = nil
    currentScreen = .registration
    navigationPath.removeAll()
  }

  func navigateToMain(accountId: UUID, membershipId: UUID) {
    startupNotice = nil
    navigationPath.removeAll()
    clearViewModelCache()
    guard dependencies.activateAccountDatabase(accountId: accountId) else {
      AppLogger.app.error(
        "AppCoordinator: refusing to enter main without active account database for accountId=\(accountId.uuidString, privacy: .public)"
      )
      currentScreen = .error(
        message: String(localized: "Failed to open local account storage. Restart the app and try again.")
      )
      return
    }
    currentScreen = .main
    dependencies.startRealtimeServices()
    Task {
      await dependencies.applicationStateManager.transitionToAuthenticated(
        membershipId: membershipId.uuidString
      )
    }
  }

  func navigateToWelcome(clearStartupNotice: Bool = true) {
    if clearStartupNotice {
      startupNotice = nil
    }
    currentScreen = .welcome
    navigationPath.removeAll()
    clearViewModelCache()
    dependencies.deactivateAccountDatabase()
    Task { [dependencies] in
      await dependencies.stopRealtimeServices()
      await dependencies.applicationStateManager.transitionToAnonymous()
    }
  }

  func startRegistration() {
    navigationPath.append(.mobileVerification(context: .registration))
  }

  func continueToOtpVerification(
    sessionId: String,
    mobileNumber: String,
    context: AuthenticationFlowContext
  ) {
    navigationPath.append(
      .otpVerification(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context
      )
    )
  }

  func continueToSecureKey(
    sessionId: String,
    mobileNumber: String,
    context: AuthenticationFlowContext,
    membershipId: UUID?,
    membershipIdBytes: Data? = nil
  ) {
    navigationPath.append(
      .secureKeyConfirmation(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context,
        membershipId: membershipId,
        membershipIdBytes: membershipIdBytes
      )
    )
  }

  func continueToPinSetup(
    sessionId: String,
    mobileNumber: String,
    context: AuthenticationFlowContext = .registration
  ) {
    navigationPath.append(
      .pinSetup(
        sessionId: sessionId,
        mobileNumber: mobileNumber,
        context: context
      )
    )
  }

  func presentPendingRegistration(_ route: PendingRegistrationRoute) {
    startupNotice = nil
    currentScreen = .registration
    navigationPath.removeAll()
    switch route {
    case .start:
      return
    case .secureKey(let membershipId, let mobileNumber, let membershipIdBytes):
      navigationPath.append(
        .secureKeyConfirmation(
          sessionId: "",
          mobileNumber: mobileNumber,
          context: .registration,
          membershipId: membershipId,
          membershipIdBytes: membershipIdBytes
        )
      )
    case .pinSetup(let mobileNumber):
      navigationPath.append(
        .pinSetup(
          sessionId: "",
          mobileNumber: mobileNumber,
          context: .registration
        )
      )
    case .completeProfile(let mobileNumber):
      navigationPath.append(
        .completeProfile(
          sessionId: "",
          mobileNumber: mobileNumber
        )
      )
    }
  }

  func continueToCompleteProfile(sessionId: String, mobileNumber: String) {
    navigationPath.append(.completeProfile(sessionId: sessionId, mobileNumber: mobileNumber))
  }

  func continueToPinEntry() {
    navigationPath.append(.pinEntry)
  }

  func startSignIn() {
    navigationPath.append(.signIn)
  }

  func startSecureKeyRecovery() {
    navigationPath.append(.mobileVerification(context: .secureKeyRecovery))
  }

  func popLast() {
    guard !navigationPath.isEmpty else { return }
    navigationPath.removeLast()
  }

  func popToRoot() {
    navigationPath.removeAll()
  }
}
