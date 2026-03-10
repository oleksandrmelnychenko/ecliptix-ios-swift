// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension OtpVerificationViewModel {

  func startCountdownTask(version: Int64) {
    replaceCountdownTask(with: Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        guard let self, !Task.isCancelled, self.isCountdownVersionCurrent(version) else { return }
        if self.secondsRemaining > 0 {
          self.secondsRemaining -= 1
          self.updateRemainingTimeDisplay()
        } else {
          self.handleExpiredStatus()
          return
        }
      }
    })
  }

  func startCooldownTask() {
    replaceCooldownTask(with: Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        guard let self, !Task.isCancelled else { return }
        if self.cooldownBufferSeconds > 0 {
          self.cooldownBufferSeconds -= 1
          if self.cooldownBufferSeconds == 0 {
            self.errorMessage = ""
            self.hasError = false
            self.currentStatus = .expired
            return
          }
        } else {
          return
        }
      }
    })
  }

  func updateRemainingTimeDisplay() {
    let minutes = secondsRemaining / 60
    let seconds = secondsRemaining % 60
    remainingTime = String(format: "%02d:%02d", minutes, seconds)
  }

  func handleExpiredStatus() {
    secondsRemaining = 0
    currentStatus = .expired
    remainingTime = "EXPIRED"
    if hasError {
      errorMessage = ""
      hasError = false
    }
  }

  func handleRateLimitExceeded() {
    guard !alreadyVerifiedHandled, tryStartAutoRedirectOnce() else { return }
    isMaxAttemptsReached = true
    hasValidSession = false
    currentStatus = .maxAttemptsReached
    cancelAllTasks()
    publishError(String(localized: "Too many attempts. Returning to start..."))
    startAutoRedirect(
      seconds: AppConstants.Otp.autoRedirectMediumDelaySeconds,
      title: String(localized: "Security Limit Reached"),
      subtitle: String(localized: "Please try again later"))
  }
}
