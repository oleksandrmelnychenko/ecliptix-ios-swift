// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

@Observable @MainActor
final class WelcomeBackViewModel {

  var isBusy: Bool = false
  var errorMessage: String = ""
  var hasError: Bool = false
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let onContinueToSetup: (UUID, String, Data?) -> Void
  private let onContinueLater: () -> Void

  init(
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    onContinueToSetup: @escaping (UUID, String, Data?) -> Void = { _, _, _ in },
    onContinueLater: @escaping () -> Void = {}
  ) {
    self.settingsProvider = settingsProvider
    self.onContinueToSetup = onContinueToSetup
    self.onContinueLater = onContinueLater
  }

  func continueToSetup() {
    guard !isBusy else { return }
    isBusy = true
    defer { isBusy = false }

    guard let settings = settingsProvider(),
      let membership = settings.membership,
      !membership.membershipId.isZero
    else {
      errorMessage = String(localized: "No incomplete registration found")
      hasError = true
      return
    }
    onContinueToSetup(
      membership.membershipId,
      membership.mobileNumber,
      membership.membershipId.protobufBytes
    )
  }

  func continueLater() {
    onContinueLater()
  }
}
