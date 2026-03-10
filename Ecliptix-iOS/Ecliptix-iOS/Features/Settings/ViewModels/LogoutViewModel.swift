// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os.log

@Observable @MainActor
final class LogoutViewModel {

  var isLoggingOut: Bool = false
  var errorMessage: String = ""
  var hasError: Bool = false
  private let logoutService: LogoutService

  init(logoutService: LogoutService) {
    self.logoutService = logoutService
  }

  func confirmLogout() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    errorMessage = ""
    hasError = false
    let result = await logoutService.logoutAsync(reason: .userInitiated)
    if let failure = result.err() {
      AppLogger.auth.warning(
        "[LOGOUT-VM] Logout completed with failure: \(failure.message, privacy: .public)")
      errorMessage = failure.message
      hasError = true
    }
    isLoggingOut = false
  }
}
