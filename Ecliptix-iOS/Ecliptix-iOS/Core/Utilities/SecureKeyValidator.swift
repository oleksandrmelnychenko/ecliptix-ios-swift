// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum SecureKeyStrength: String {
  case invalid = "INVALID"
  case veryWeak = "VERY_WEAK"
  case weak = "WEAK"
  case good = "GOOD"
  case strong = "STRONG"
  case veryStrong = "VERY_STRONG"
  var localizedName: String {
    switch self {
    case .invalid: return String(localized: "Invalid")
    case .veryWeak: return String(localized: "Very Weak")
    case .weak: return String(localized: "Weak")
    case .good: return String(localized: "Good")
    case .strong: return String(localized: "Strong")
    case .veryStrong: return String(localized: "Very Strong")
    }
  }
}

enum SecureKeyValidatorConstants {
  enum LocalizationKeys {
    static let required = "ValidationErrors.SecureKey.REQUIRED"
    static let nonEnglishLetters = "ValidationErrors.SecureKey.NON_ENGLISH_LETTERS"
    static let noSpaces = "ValidationErrors.SecureKey.NO_SPACES"
    static let minLength = "ValidationErrors.SecureKey.MIN_LENGTH"
    static let noUppercase = "ValidationErrors.SecureKey.NO_UPPERCASE"
    static let noLowercase = "ValidationErrors.SecureKey.NO_LOWERCASE"
    static let noSpecialChar = "ValidationErrors.SecureKey.NO_SPECIAL_CHAR"
    static let noDigit = "ValidationErrors.SecureKey.NO_DIGIT"
    static let maxLength = "ValidationErrors.SecureKey.MAX_LENGTH"
    static let tooSimple = "ValidationErrors.SecureKey.TOO_SIMPLE"
    static let tooCommon = "ValidationErrors.SecureKey.TOO_COMMON"
    static let sequentialPattern = "ValidationErrors.SecureKey.SEQUENTIAL_PATTERN"
    static let repeatedChars = "ValidationErrors.SecureKey.REPEATED_CHARS"
    static let lacksDiversity = "ValidationErrors.SecureKey.LACKS_DIVERSITY"
    static let containsAppName = "ValidationErrors.SecureKey.CONTAINS_APP_NAME"
  }

  enum ValidationRules {

    static let minLength = 8
    static let maxLength = 21
    static let minCharClasses = 2
    static let minTotalEntropyBits: Double = 50.0
  }

  static let keyboardRows: Set<String> = [
    "qwertyuiop",
    "asdfghjkl",
    "zxcvbnm",
    "1234567890",
  ]
  static let appNameVariants: Set<String> = [
    "ecliptix",
    "eclip",
    "opaque",
  ]
  static let commonlyUsedSecureKeys: Set<String> = [
    "123456", "password", "12345678", "123456789", "qwerty",
    "abc123", "monkey", "1234567", "letmein", "trustno1",
    "dragon", "baseball", "iloveyou", "master", "sunshine",
    "ashley", "football", "shadow", "123123", "654321",
    "superman", "qazwsx", "michael", "password1", "password123",
    "welcome", "1234567890", "admin", "login", "princess",
  ]
}

enum SecureKeyValidator {

  private static let asciiLetters = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
  )
  private static let asciiAlphanumeric = CharacterSet(
    charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
  )
  private typealias HardRule = (isInvalid: (String) -> Bool, errorKey: String, args: [Int])
  private typealias SoftRule = (isWeak: (String) -> Bool, errorKey: String, args: [Int])

  private static func getHardRules() -> [HardRule] {
    [
      (
        { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
        SecureKeyValidatorConstants.LocalizationKeys.required,
        []
      ),
      (
        { hasNonEnglishLetters($0) },
        SecureKeyValidatorConstants.LocalizationKeys.nonEnglishLetters,
        []
      ),
      (
        { $0.unicodeScalars.contains { CharacterSet.whitespaces.contains($0) } },
        SecureKeyValidatorConstants.LocalizationKeys.noSpaces,
        []
      ),
      (
        { $0.count < SecureKeyValidatorConstants.ValidationRules.minLength },
        SecureKeyValidatorConstants.LocalizationKeys.minLength,
        [SecureKeyValidatorConstants.ValidationRules.minLength]
      ),
      (
        { !hasUppercase($0) },
        SecureKeyValidatorConstants.LocalizationKeys.noUppercase,
        []
      ),
      (
        { !hasLowercase($0) },
        SecureKeyValidatorConstants.LocalizationKeys.noLowercase,
        []
      ),
      (
        { !hasSpecialCharacter($0) },
        SecureKeyValidatorConstants.LocalizationKeys.noSpecialChar,
        []
      ),
      (
        { !hasDigit($0) },
        SecureKeyValidatorConstants.LocalizationKeys.noDigit,
        []
      ),
    ]
  }

  private static func getSoftRules() -> [SoftRule] {
    [
      (
        { $0.count > SecureKeyValidatorConstants.ValidationRules.maxLength },
        SecureKeyValidatorConstants.LocalizationKeys.maxLength,
        [SecureKeyValidatorConstants.ValidationRules.maxLength]
      ),
      (
        { SecureKeyValidatorConstants.commonlyUsedSecureKeys.contains($0.lowercased()) },
        SecureKeyValidatorConstants.LocalizationKeys.tooCommon,
        []
      ),
      (
        { isSequentialOrKeyboardPattern($0) },
        SecureKeyValidatorConstants.LocalizationKeys.sequentialPattern,
        []
      ),
      (
        { hasExcessiveRepeats($0) },
        SecureKeyValidatorConstants.LocalizationKeys.repeatedChars,
        []
      ),
      (
        { lacksCharacterDiversity($0) },
        SecureKeyValidatorConstants.LocalizationKeys.lacksDiversity,
        [SecureKeyValidatorConstants.ValidationRules.minCharClasses]
      ),
      (
        { containsAppNameVariant($0) },
        SecureKeyValidatorConstants.LocalizationKeys.containsAppName,
        []
      ),
      (
        {
          calculateTotalShannonEntropy($0)
            < SecureKeyValidatorConstants.ValidationRules.minTotalEntropyBits
        },
        SecureKeyValidatorConstants.LocalizationKeys.tooSimple,
        []
      ),
    ]
  }

  static func validate(
    _ secureKey: String,
    localization: LocalizationProviding
  ) -> (error: String?, recommendations: [String]) {
    var recommendations: [String] = []
    let s = secureKey
    for rule in getHardRules() {
      if rule.isInvalid(s) {
        let error = formatMessage(localization.getString(rule.errorKey), args: rule.args)
        return (error, recommendations)
      }
    }
    for rule in getSoftRules() {
      if rule.isWeak(s) {
        recommendations.append(
          formatMessage(localization.getString(rule.errorKey), args: rule.args)
        )
      }
    }
    return (nil, recommendations)
  }

  static func getChecklistStatus(
    _ secureKey: String,
    localization: LocalizationProviding
  ) -> [(description: String, isMet: Bool)] {
    let s = secureKey
    let hardRules = getHardRules()
    let checklistKeys = [
      SecureKeyValidatorConstants.LocalizationKeys.minLength,
      SecureKeyValidatorConstants.LocalizationKeys.noUppercase,
      SecureKeyValidatorConstants.LocalizationKeys.noLowercase,
      SecureKeyValidatorConstants.LocalizationKeys.noSpecialChar,
      SecureKeyValidatorConstants.LocalizationKeys.noDigit,
    ]
    var statusList: [(description: String, isMet: Bool)] = []
    for key in checklistKeys {
      if let rule = hardRules.first(where: { $0.errorKey == key }) {
        let isMet = !rule.isInvalid(s)
        let description = formatMessage(localization.getString(key), args: rule.args)
        statusList.append((description, isMet))
      }
    }
    return statusList
  }

  static func estimateStrength(
    _ secureKey: String,
    localization: LocalizationProviding
  ) -> SecureKeyStrength {
    if secureKey.isEmpty {
      return .invalid
    }

    let (hardError, _) = validate(secureKey, localization: localization)
    if hardError != nil {
      return .invalid
    }

    let softTips = getQualityRecommendations(secureKey, localization: localization)
    let penalties = softTips.count
    let lengthScore: Int
    switch secureKey.count {
    case 14...: lengthScore = 3
    case 12...: lengthScore = 2
    case 10...: lengthScore = 1
    default: lengthScore = 0
    }

    let finalScore = lengthScore - penalties
    switch finalScore {
    case ...0: return .weak
    case 1: return .good
    case 2: return .strong
    default: return .veryStrong
    }
  }

  static func getQualityRecommendations(
    _ secureKey: String,
    localization: LocalizationProviding
  ) -> [String] {
    var recommendations: [String] = []
    let s = secureKey
    guard !s.isEmpty else { return recommendations }
    for rule in getSoftRules() {
      if rule.isWeak(s) {
        recommendations.append(
          formatMessage(localization.getString(rule.errorKey), args: rule.args)
        )
      }
    }
    return recommendations
  }

  @inline(never)
  static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    guard aBytes.count == bBytes.count else { return false }
    return aBytes.withUnsafeBufferPointer { aPtr in
      bBytes.withUnsafeBufferPointer { bPtr in
        timingsafe_bcmp(aPtr.baseAddress!, bPtr.baseAddress!, aBytes.count) == 0
      }
    }
  }

  private static func hasNonEnglishLetters(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
      CharacterSet.letters.contains(scalar) && !asciiLetters.contains(scalar)
    }
  }

  private static func hasUppercase(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
      scalar.value >= 0x41 && scalar.value <= 0x5A
    }
  }

  private static func hasLowercase(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
      scalar.value >= 0x61 && scalar.value <= 0x7A
    }
  }

  private static func hasDigit(_ s: String) -> Bool {
    s.unicodeScalars.contains { scalar in
      scalar.value >= 0x30 && scalar.value <= 0x39
    }
  }

  private static func hasSpecialCharacter(_ s: String) -> Bool {
    s.unicodeScalars.contains { !asciiAlphanumeric.contains($0) }
  }

  private static func isSequentialOrKeyboardPattern(_ s: String) -> Bool {
    let patternLen = 4
    guard s.count >= patternLen else { return false }
    let lowered = s.lowercased()
    let chars = Array(lowered)
    for i in 0...(chars.count - patternLen) {
      let sub = String(chars[i..<(i + patternLen)])
      if isCharSequence(sub) {
        return true
      }
      if SecureKeyValidatorConstants.keyboardRows.contains(where: { $0.contains(sub) }) {
        return true
      }

      let reversed = String(sub.reversed())
      if SecureKeyValidatorConstants.keyboardRows.contains(where: { $0.contains(reversed) }) {
        return true
      }
    }
    return false
  }

  private static func isCharSequence(_ sub: String) -> Bool {
    let scalars = Array(sub.unicodeScalars)
    guard scalars.count >= 2 else { return false }
    var asc = true
    var desc = true
    for j in 1..<scalars.count {
      if scalars[j].value != scalars[j - 1].value &+ 1 {
        asc = false
      }
      if scalars[j].value != scalars[j - 1].value &- 1 {
        desc = false
      }
    }
    return asc || desc
  }

  private static func hasExcessiveRepeats(_ s: String) -> Bool {
    guard s.count >= 4 else { return false }
    let chars = Array(s)
    for i in 0...(chars.count - 4) {
      if chars[i] == chars[i + 1] && chars[i] == chars[i + 2] && chars[i] == chars[i + 3] {
        return true
      }
    }
    return false
  }

  private static func lacksCharacterDiversity(_ s: String) -> Bool {
    getCharacterClassCount(s) < SecureKeyValidatorConstants.ValidationRules.minCharClasses
  }

  private static func getCharacterClassCount(_ s: String) -> Int {
    var classes = 0
    if hasLowercase(s) { classes += 1 }
    if hasUppercase(s) { classes += 1 }
    if hasDigit(s) { classes += 1 }
    if hasSpecialCharacter(s) { classes += 1 }
    return classes
  }

  private static func containsAppNameVariant(_ s: String) -> Bool {
    let lowered = s.lowercased()
    return SecureKeyValidatorConstants.appNameVariants.contains { lowered.contains($0) }
  }

  static func calculateTotalShannonEntropy(_ s: String) -> Double {
    guard !s.isEmpty else { return 0 }
    var freqMap: [Character: Int] = [:]
    for char in s {
      freqMap[char, default: 0] += 1
    }

    let totalLength = Double(s.count)
    let perCharEntropy = freqMap.values
      .map { Double($0) / totalLength }
      .reduce(0.0) { $0 + (-$1 * log2($1)) }
    return perCharEntropy * totalLength
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
