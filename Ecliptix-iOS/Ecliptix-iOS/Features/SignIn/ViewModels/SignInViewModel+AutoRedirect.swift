// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension SignInViewModel {

  func handleSignInFailure(type: AuthenticationFailureType, message: String) {
    hasSecureKeyBeenTouched = true
    serverFailureType = type
    if type == .registrationRequired {
      serverError = message
      errorMessage = message
      hasError = true
      startAutoRedirect(
        seconds: 5, title: String(localized: "Registration Required"),
        subtitle: String(localized: "Account not found"), message: message)
    } else if isRateLimitError(type: type, message: message) {
      serverError = message
      errorMessage = message
      hasError = true
      startAutoRedirect(
        seconds: 10, title: String(localized: "Security Limit Reached"),
        subtitle: String(localized: "Too many failed attempts"), message: message)
    } else {
      serverError = message
      errorMessage = message
      hasError = false
    }
  }

  func isRateLimitError(type: AuthenticationFailureType, message: String) -> Bool {
    if type == .loginAttemptExceeded { return true }
    let keywords = ["too many", "rate limit", "locked", "attempts exceeded", "try again later"]
    return keywords.contains { message.lowercased().contains($0) }
  }

  func startAutoRedirect(seconds: Int, title: String, subtitle: String, message: String) {
    isAutoRedirecting = true
    autoRedirectTitle = title
    autoRedirectSubtitle = subtitle
    autoRedirectCountdown = max(seconds, 0)
    errorMessage = message
    hasError = true
    autoRedirectTimer.start(
      seconds: seconds,
      onTick: { [weak self] remaining in
        self?.autoRedirectCountdown = remaining
      },
      onFinish: { [weak self] in
        guard let self else { return }
        self.autoRedirectCountdown = 0
        self.isAutoRedirecting = false
        self.onAutoRedirectComplete()
      }
    )
  }
}
