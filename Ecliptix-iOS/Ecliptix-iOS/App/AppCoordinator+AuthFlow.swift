// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

@MainActor
extension AppCoordinator {

  func handleLogout() {
    navigateToWelcome()
  }

  func completeRegistration(accountId: UUID, membershipId: UUID) {
    navigationPath.removeAll()
    navigateToMain(accountId: accountId, membershipId: membershipId)
  }

  func completeSignIn(accountId: UUID, membershipId: UUID) {
    navigationPath.removeAll()
    navigateToMain(accountId: accountId, membershipId: membershipId)
  }

  func completeSignInFromStoredState(creationStatus: SignInCreationStatus = .pinCredentialSet) {
    switch dependencies.appFlowResolver.resolveStoredSignInDecision(
      creationStatus: creationStatus,
      storedIdentity: dependencies.resolveStoredIdentity()
    ) {
    case .signIn:
      navigateToSignIn()
    case .pinSetup:
      continueToPinSetup(
        sessionId: "",
        mobileNumber: "",
        context: .signIn
      )
    case .pinEntry:
      continueToPinEntry()
    }
  }

  func completeSignInAfterPin() {
    guard let storedIdentity = dependencies.resolveStoredIdentity() else {
      navigateToSignIn()
      return
    }
    completeSignIn(
      accountId: storedIdentity.accountId,
      membershipId: storedIdentity.membershipId
    )
  }

  func completeRegistrationFromStoredState() {
    switch dependencies.appFlowResolver.resolveStoredRegistrationDecision(
      settings: dependencies.currentAppSettings(),
      storedIdentity: dependencies.resolveStoredIdentity()
    ) {
    case .main(let accountId, let membershipId):
      completeRegistration(
        accountId: accountId,
        membershipId: membershipId
      )
    case .pendingRegistration(let route):
      presentPendingRegistration(route)
    }
  }
}
