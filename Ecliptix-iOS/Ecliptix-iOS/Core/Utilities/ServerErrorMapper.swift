// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

enum ServerErrorMapper {

  private static let transportErrorPattern = /^Transport error \[([^\]]+)\](?:: (.+))?/

  static func userFacingMessage(_ raw: String) -> String {
    if let match = raw.firstMatch(of: transportErrorPattern) {
      let code = String(match.1)
      if let serverMessage = match.2 {
        let trimmed = String(serverMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, !prefersMappedMessage(for: code) {
          return trimmed
        }
      }
      return mapServerErrorCode(code)
    }

    if raw.hasPrefix("error.") {
      return mapI18nKey(raw)
    }

    let lower = raw.lowercased()

    if lower.contains("unavailable") || lower.contains("connection refused")
      || lower.contains("timeout") || lower.contains("no route")
      || lower.contains("network") || lower.contains("dns")
      || lower.contains("could not connect")
    {
      return String(localized: "Connection error. Please check your internet and try again.")
    }

    if lower.contains("rate limit") || lower.contains("too many")
      || lower.contains("attempts exceeded") || lower.contains("try again later")
      || lower.contains("locked")
    {
      return String(localized: "Too many attempts. Please try again later.")
    }

    return raw
  }

  static func prefersMappedMessage(for code: String) -> Bool {
    switch code {
    case ServerErrorCode.Otp.resendCooldown:
      return true
    default:
      return false
    }
  }

  private static func mapI18nKey(_ key: String) -> String {
    switch key {
    case ErrorI18NKeys.invalidCredentials:
      return String(localized: "Incorrect mobile number or password")
    case ErrorI18NKeys.loginAttemptExceeded:
      return String(localized: "Too many failed attempts. Please try again later.")
    case ErrorI18NKeys.serviceUnavailable, ErrorI18NKeys.dependencyUnavailable:
      return String(localized: "Service temporarily unavailable. Please try again.")
    case ErrorI18NKeys.maxAttempts, ErrorI18NKeys.resourceExhausted:
      return String(localized: "Too many attempts. Please try again later.")
    case ErrorI18NKeys.notFound:
      return String(localized: "Account not found. Please check your details.")
    case ErrorI18NKeys.validation:
      return String(localized: "Please check your input and try again.")
    case ErrorI18NKeys.unauthenticated:
      return String(localized: "Authentication failed. Please try again.")
    case ErrorI18NKeys.mobileNumberRequired:
      return String(localized: "Mobile number is required")
    case ErrorI18NKeys.secureKeyRequired:
      return String(localized: "Password is required")
    case ErrorI18NKeys.mobileAlreadyRegistered:
      return String(localized: "This mobile number is already registered")
    case ErrorI18NKeys.registrationInitFailed, ErrorI18NKeys.registrationCompleteFailed:
      return String(localized: "Registration failed. Please try again.")
    case ErrorI18NKeys.recoveryInitFailed:
      return String(localized: "Recovery failed. Please try again.")
    case ErrorI18NKeys.opaqueOperationFailed:
      return String(localized: "Authentication failed. Please try again.")
    default:
      return mapServerErrorCode(key)
    }
  }

  static func mapServerErrorCode(_ key: String) -> String {
    switch key {
    case ServerErrorCode.Error.internal, ServerErrorCode.Error.grpc:
      return String(localized: "An internal error occurred. Please try again.")
    case ServerErrorCode.Error.alreadyExists:
      return String(localized: "This record already exists.")
    case ServerErrorCode.Error.rateLimitDb, ServerErrorCode.Error.flowCreate,
      ServerErrorCode.Error.flowFetch:
      return String(localized: "Service temporarily unavailable. Please try again.")
    case ServerErrorCode.Error.otpCreate, ServerErrorCode.Error.smsDelivery:
      return String(localized: "Failed to send verification code. Please try again.")

    case ServerErrorCode.Otp.expired, ServerErrorCode.Otp.codeExpired:
      return String(localized: "Verification code has expired. Please request a new one.")
    case ServerErrorCode.Otp.invalidCode:
      return String(localized: "Invalid verification code. Please try again.")
    case ServerErrorCode.Otp.sessionNotFound, ServerErrorCode.Otp.notFound:
      return String(localized: "Verification session expired. Please start over.")
    case ServerErrorCode.Otp.tooManyAttempts:
      return String(localized: "Too many attempts. Please try again later.")
    case ServerErrorCode.Otp.rateLimited, ServerErrorCode.Otp.resendCooldown,
      ServerErrorCode.Otp.countdown:
      return String(localized: "Please wait before requesting another code.")
    case ServerErrorCode.Otp.invalidPayload, ServerErrorCode.Otp.recoveryInvalidPayload:
      return String(localized: "Invalid request. Please try again.")

    case ServerErrorCode.Mobile.invalid, ServerErrorCode.Mobile.parsingInvalidNumber,
      ServerErrorCode.Mobile.parsingInvalidCountryCode:
      return String(localized: "Invalid mobile number. Please check and try again.")
    case ServerErrorCode.Mobile.cannotBeEmpty, ServerErrorCode.Phone.cannotBeEmpty:
      return String(localized: "Mobile number is required.")
    case ServerErrorCode.Mobile.parsingTooShort, ServerErrorCode.Phone.parsingTooShort:
      return String(localized: "Mobile number is too short.")
    case ServerErrorCode.Mobile.parsingTooLong, ServerErrorCode.Phone.parsingTooLong:
      return String(localized: "Mobile number is too long.")
    case ServerErrorCode.Mobile.numberTakenActive:
      return String(localized: "This mobile number is already registered.")
    case ServerErrorCode.Mobile.numberBlocked, ServerErrorCode.PhoneChange.numberBlocked:
      return String(localized: "This mobile number has been blocked.")
    case ServerErrorCode.Mobile.registrationExpired:
      return String(localized: "Registration has expired. Please start over.")

    case ServerErrorCode.Session.reinitRequired:
      return String(localized: "Session expired. Please sign in again.")
    case ServerErrorCode.Session.invalidHmac, ServerErrorCode.Session.invalidIdentityProof:
      return String(localized: "Security verification failed. Please sign in again.")
    case ServerErrorCode.Session.keyUnavailable:
      return String(localized: "Encryption keys unavailable. Please try again.")

    case ServerErrorCode.Auth.signinRateLimited, ServerErrorCode.Auth.recoveryRateLimited:
      return String(localized: "Too many sign-in attempts. Please try again later.")
    case ServerErrorCode.Auth.accountLocked, ServerErrorCode.Auth.accountLockedEscalated:
      return String(localized: "Account has been locked. Please contact support.")

    case ServerErrorCode.Pin.invalidPin:
      return String(localized: "Incorrect PIN. Please try again.")
    case ServerErrorCode.Pin.locked:
      return String(localized: "PIN locked due to too many attempts.")
    case ServerErrorCode.Pin.invalidLength:
      return String(localized: "Invalid PIN length.")
    case ServerErrorCode.Pin.notRegistered:
      return String(localized: "PIN has not been set up yet.")

    case ServerErrorCode.Recovery.codeInvalid:
      return String(localized: "Invalid recovery code.")
    case ServerErrorCode.Recovery.codeExhausted:
      return String(localized: "All recovery codes have been used.")
    case ServerErrorCode.Recovery.coolingPeriod:
      return String(localized: "Recovery is in a cooling period. Please try again later.")
    case ServerErrorCode.Recovery.rateLimited:
      return String(localized: "Too many recovery attempts. Please try again later.")
    case ServerErrorCode.Recovery.noTrustedDevices:
      return String(localized: "No trusted devices found for recovery.")
    case ServerErrorCode.Recovery.invalidCombination:
      return String(localized: "Invalid recovery combination.")

    case ServerErrorCode.Profile.notFound:
      return String(localized: "Profile not found.")
    case ServerErrorCode.Profile.upsertFailed:
      return String(localized: "Failed to update profile. Please try again.")

    case ServerErrorCode.RateLimit.mobileFlowExceeded, ServerErrorCode.RateLimit.deviceFlowExceeded,
      ServerErrorCode.RateLimit.otpSendsPerFlowExceeded,
      ServerErrorCode.RateLimit.otpSendsPerMobileExceeded,
      ServerErrorCode.RateLimit.passwordRecoveryMobileExceeded,
      ServerErrorCode.RateLimit.passwordRecoveryDeviceExceeded:
      return String(localized: "Too many requests. Please try again later.")

    case ServerErrorCode.Validation.payloadTooLarge:
      return String(localized: "Request is too large. Please try again.")
    case ServerErrorCode.Validation.fieldTooLong:
      return String(localized: "Input is too long. Please shorten and try again.")

    case ServerErrorCode.Messaging.chatUnavailable:
      return String(localized: "Chat is temporarily unavailable.")
    case ServerErrorCode.Streaming.unavailable:
      return String(localized: "Connection lost. Reconnecting...")

    case ServerErrorCode.Opaque.invalidInput, ServerErrorCode.Opaque.validationError:
      return String(localized: "Invalid input. Please try again.")
    case ServerErrorCode.Opaque.cryptoError, ServerErrorCode.Opaque.authenticationError:
      return String(localized: "Authentication failed. Please try again.")
    case ServerErrorCode.Opaque.alreadyRegistered:
      return String(localized: "This account is already registered.")

    default:
      AppLogger.app.warning("Unmapped server error code: \(key, privacy: .public)")
      return String(localized: "Something went wrong. Please try again.")
    }
  }
}
