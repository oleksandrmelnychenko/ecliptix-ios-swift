// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

enum AppTheme: String, CaseIterable, Identifiable {
  case system
  case light
  case dark
  case midnight
  case frost

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: String(localized: "System")
    case .light: String(localized: "Light")
    case .dark: String(localized: "Dark")
    case .midnight: String(localized: "Midnight")
    case .frost: String(localized: "Frost")
    }
  }

  var symbolName: String {
    switch self {
    case .system: "iphone"
    case .light: "sun.max"
    case .dark: "moon"
    case .midnight: "moon.stars"
    case .frost: "snowflake"
    }
  }

  var colorScheme: ColorScheme? {
    switch self {
    case .system: nil
    case .light, .frost: .light
    case .dark, .midnight: .dark
    }
  }

  var previewColor: Color {
    switch self {
    case .system: .ecliptixSurface
    case .light: .white
    case .dark: Color(hex: 0x1A1A1A)
    case .midnight: .black
    case .frost: Color(hex: 0xF0F4FF)
    }
  }
}

enum AccentColor: String, CaseIterable, Identifiable {
  case blue
  case indigo
  case purple
  case pink
  case orange
  case teal
  case green

  var id: String { rawValue }

  var color: Color {
    switch self {
    case .blue:
      Color(
        uiColor: UIColor { traits in
          traits.userInterfaceStyle == .dark
            ? UIColor(red: 0x4F / 255.0, green: 0x9C / 255.0, blue: 0xFF / 255.0, alpha: 1)
            : UIColor(red: 0x09 / 255.0, green: 0x69 / 255.0, blue: 0xDA / 255.0, alpha: 1)
        })
    case .indigo: Color(hex: 0x5856D6)
    case .purple: Color(hex: 0xA855F7)
    case .pink: Color(hex: 0xEC4899)
    case .orange: Color(hex: 0xF97316)
    case .teal: Color(hex: 0x14B8A6)
    case .green: Color(hex: 0x10A37F)
    }
  }

  var title: String {
    switch self {
    case .blue: String(localized: "Blue")
    case .indigo: String(localized: "Indigo")
    case .purple: String(localized: "Purple")
    case .pink: String(localized: "Pink")
    case .orange: String(localized: "Orange")
    case .teal: String(localized: "Teal")
    case .green: String(localized: "Green")
    }
  }
}
