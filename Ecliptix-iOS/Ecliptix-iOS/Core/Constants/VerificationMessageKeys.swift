// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum VerificationMessageKeys {

  static let resendCooldown = "resend_cooldown_active"
  static let otpMaxAttemptsReached = "max_otp_attempts_reached"
  static let securityRateLimitExceeded = "security_rate_limit_exceeded"
  static let deviceRateLimitExceeded = "device_rate_limit_exceeded"
  static let mobileOtpLimitExhausted = "mobile_otp_limit_exhausted"
  static let otpExpired = "otp_expired"
  static let verificationFlowExpired = "verification_flow_expired"
  static let rateLimitKeys: Set<String> = [
    otpMaxAttemptsReached,
    securityRateLimitExceeded,
    deviceRateLimitExceeded,
    mobileOtpLimitExhausted,
  ]

  static func isRateLimitKey(_ normalizedKey: String) -> Bool {
    rateLimitKeys.contains(normalizedKey)
  }

  static func normalizedKey(in raw: String) -> String? {
    let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if normalized.isEmpty {
      return nil
    }

    let knownKeys = rateLimitKeys.union([
      resendCooldown,
      otpExpired,
      verificationFlowExpired,
    ])
    if knownKeys.contains(normalized) {
      return normalized
    }

    return knownKeys.first(where: { normalized.contains($0) })
  }
}
