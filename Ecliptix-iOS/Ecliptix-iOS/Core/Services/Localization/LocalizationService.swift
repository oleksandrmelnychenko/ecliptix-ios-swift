// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

protocol LocalizationProviding {

  func getString(_ key: String) -> String

  func setCulture(_ culture: String)
}

final class LocalizationService: LocalizationProviding {

  static let shared = LocalizationService()
  private(set) var currentCulture: String = "en-US"
  private static let fallbacks: [String: String] = [
    ErrorI18NKeys.mobileNumberRequired: "Mobile number is required",
    ErrorI18NKeys.secureKeyRequired: "Secure key is required",
    ErrorI18NKeys.invalidCredentials: "Invalid credentials",
    ErrorI18NKeys.loginAttemptExceeded: "Too many login attempts",
    ErrorI18NKeys.keyExchangeUnavailable: "Key exchange data unavailable",
    ErrorI18NKeys.membershipMissing: "Membership is missing in sign-in response",
    ErrorI18NKeys.invalidMembershipId: "Invalid membership identifier",
    ErrorI18NKeys.invalidAccountId: "Invalid account identifier",
    ErrorI18NKeys.opaqueOperationFailed: "Authentication operation failed",
    ErrorI18NKeys.registrationInProgress: "Registration already in progress",
    ErrorI18NKeys.membershipIdRequired: "Membership identifier is required",
    ErrorI18NKeys.registrationRequestUnavailable: "Registration request data unavailable",
    ErrorI18NKeys.registrationInitFailed: "Registration initialization failed",
    ErrorI18NKeys.registrationCompleteFailed: "Registration completion failed",
    ErrorI18NKeys.mobileValidationEmpty: "Mobile number validation failed",
    ErrorI18NKeys.mobileAlreadyRegistered: "This mobile number is already registered",
    ErrorI18NKeys.mobileDataCorrupted: "Mobile number data is corrupted",
    ErrorI18NKeys.mobileNotAvailable: "Mobile number is not available for registration",
    ErrorI18NKeys.recoveryInProgress: "Recovery already in progress",
    ErrorI18NKeys.recoveryRequestUnavailable: "Recovery request data unavailable",
    ErrorI18NKeys.recoveryInitFailed: "Recovery initialization failed",
    ErrorI18NKeys.serviceUnavailable: "Service is temporarily unavailable",
    ErrorI18NKeys.unauthenticated: "Authentication required",
    ErrorI18NKeys.maxAttempts: "Maximum attempts exceeded",
    ErrorI18NKeys.notFound: "Resource not found",
    ErrorI18NKeys.validation: "Validation failed",
    SecureKeyValidatorConstants.LocalizationKeys.required: "Secure key is required",
    SecureKeyValidatorConstants.LocalizationKeys.nonEnglishLetters:
      "Only English letters are allowed",
    SecureKeyValidatorConstants.LocalizationKeys.noSpaces: "Spaces are not allowed",
    SecureKeyValidatorConstants.LocalizationKeys.minLength: "At least {0} characters long",
    SecureKeyValidatorConstants.LocalizationKeys.noUppercase: "Contains uppercase letter",
    SecureKeyValidatorConstants.LocalizationKeys.noLowercase: "Contains lowercase letter",
    SecureKeyValidatorConstants.LocalizationKeys.noSpecialChar: "Contains special character",
    SecureKeyValidatorConstants.LocalizationKeys.noDigit: "Contains number",
    SecureKeyValidatorConstants.LocalizationKeys.maxLength: "Maximum {0} characters recommended",
    SecureKeyValidatorConstants.LocalizationKeys.tooSimple: "Key is too simple or predictable",
    SecureKeyValidatorConstants.LocalizationKeys.tooCommon: "This is a commonly used key",
    SecureKeyValidatorConstants.LocalizationKeys.sequentialPattern:
      "Avoid sequential or keyboard patterns",
    SecureKeyValidatorConstants.LocalizationKeys.repeatedChars: "Avoid repeating characters",
    SecureKeyValidatorConstants.LocalizationKeys.lacksDiversity: "Use at least {0} character types",
    SecureKeyValidatorConstants.LocalizationKeys.containsAppName: "Should not contain the app name",
    MobileNumberValidatorConstants.LocalizationKeys.cannotBeEmpty: "Mobile number is required",
    MobileNumberValidatorConstants.LocalizationKeys.containsNonDigits:
      "Mobile number must contain only digits",
    MobileNumberValidatorConstants.LocalizationKeys.incorrectLength:
      "Mobile number must be {0}-{1} digits",
  ]

  func setCulture(_ culture: String) {
    currentCulture = culture.isEmpty ? "en-US" : culture
  }

  func getString(_ key: String) -> String {
    let localized = String(localized: String.LocalizationValue(key))
    if localized == key {
      return Self.fallbacks[key] ?? key
    }
    return localized
  }
}
