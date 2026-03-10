// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension SecureKeyConfirmationViewModel {

  func validateSecureKey() {
    let checklist = SecureKeyValidator.getChecklistStatus(secureKey, localization: localization)
    validationTips = checklist.map {
      RequirementItem(description: $0.description, isSatisfied: $0.isMet)
    }

    let (hardError, softRecommendations) = SecureKeyValidator.validate(
      secureKey, localization: localization
    )
    recommendations = softRecommendations
    if let hardError {
      secureKeyError = hardError
      isSecureKeySuccess = false
      currentSecureKeyStrength = .invalid
      secureKeyStrengthMessage = currentSecureKeyStrength.localizedName
      return
    }
    secureKeyError = ""
    isSecureKeySuccess = true
    let strength = SecureKeyValidator.estimateStrength(secureKey, localization: localization)
    currentSecureKeyStrength = strength
    secureKeyStrengthMessage = strength.localizedName
  }

  func validateVerifySecureKey() {
    if verifySecureKey.isEmpty {
      verifySecureKeyError = String(localized: "Please confirm your secure key")
      return
    }
    verifySecureKeyError =
      !SecureKeyValidator.constantTimeEquals(secureKey, verifySecureKey)
      ? String(localized: "Secure keys do not match") : ""
  }

  func initializeValidationTips() {
    let checklist = SecureKeyValidator.getChecklistStatus("", localization: localization)
    validationTips = checklist.map {
      RequirementItem(description: $0.description, isSatisfied: $0.isMet)
    }
  }
}
