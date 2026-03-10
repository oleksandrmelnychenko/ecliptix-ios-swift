// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum MobileNumberValidatorConstants {

  enum LocalizationKeys {
    static let cannotBeEmpty = "ValidationErrors.MobileNumber.CANNOT_BE_EMPTY"
    static let containsNonDigits = "ValidationErrors.MobileNumber.CONTAINS_NON_DIGITS"
    static let incorrectLength = "ValidationErrors.MobileNumber.INCORRECT_LENGTH"
  }

  enum ValidationRules {
    static let minDigits = 7
    static let maxDigits = 15
  }
}

enum PhoneNumberValidator {

  private static let localization: LocalizationProviding = LocalizationService.shared

  static func cleanedNumber(_ number: String) -> String {
    number.replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "-", with: "")
  }

  static func validate(_ number: String) -> String? {
    if number.isEmpty {
      return localization.getString(MobileNumberValidatorConstants.LocalizationKeys.cannotBeEmpty)
    }

    let cleaned = cleanedNumber(number)
    guard cleaned.allSatisfy({ $0.isNumber }) else {
      return localization.getString(
        MobileNumberValidatorConstants.LocalizationKeys.containsNonDigits)
    }
    guard
      cleaned.count >= MobileNumberValidatorConstants.ValidationRules.minDigits
        && cleaned.count <= MobileNumberValidatorConstants.ValidationRules.maxDigits
    else {
      return formatMessage(
        localization.getString(MobileNumberValidatorConstants.LocalizationKeys.incorrectLength),
        args: [
          MobileNumberValidatorConstants.ValidationRules.minDigits,
          MobileNumberValidatorConstants.ValidationRules.maxDigits,
        ]
      )
    }
    return nil
  }

  private static func formatMessage(_ template: String, args: [Int]) -> String {
    guard !args.isEmpty else { return template }
    var result = template
    for (i, arg) in args.enumerated() {
      result = result.replacingOccurrences(of: "{\(i)}", with: "\(arg)")
    }
    return result
  }
}
