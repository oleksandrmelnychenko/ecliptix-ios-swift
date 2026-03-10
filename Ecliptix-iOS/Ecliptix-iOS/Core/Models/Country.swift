// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct Country: Identifiable, Equatable {

  let code: String
  let name: String
  let dialCode: String
  let flag: String
  var id: String { code }
  static let unitedStates = Country(code: "US", name: "United States", dialCode: "+1", flag: "🇺🇸")
  static let allCountries: [Country] = [
    .unitedStates,
    Country(code: "CA", name: "Canada", dialCode: "+1", flag: "🇨🇦"),
    Country(code: "GB", name: "United Kingdom", dialCode: "+44", flag: "🇬🇧"),
    Country(code: "UA", name: "Ukraine", dialCode: "+380", flag: "🇺🇦"),
    Country(code: "PL", name: "Poland", dialCode: "+48", flag: "🇵🇱"),
    Country(code: "DE", name: "Germany", dialCode: "+49", flag: "🇩🇪"),
    Country(code: "FR", name: "France", dialCode: "+33", flag: "🇫🇷"),
    Country(code: "ES", name: "Spain", dialCode: "+34", flag: "🇪🇸"),
    Country(code: "IT", name: "Italy", dialCode: "+39", flag: "🇮🇹"),
    Country(code: "NL", name: "Netherlands", dialCode: "+31", flag: "🇳🇱"),
    Country(code: "AU", name: "Australia", dialCode: "+61", flag: "🇦🇺"),
    Country(code: "JP", name: "Japan", dialCode: "+81", flag: "🇯🇵"),
  ]

  static func fromRegionCode(_ regionCode: String) -> Country? {
    allCountries.first { $0.code.caseInsensitiveCompare(regionCode) == .orderedSame }
  }
}
