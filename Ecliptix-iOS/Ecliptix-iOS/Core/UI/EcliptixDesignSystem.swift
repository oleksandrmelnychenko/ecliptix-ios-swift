// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI
import UIKit

extension Color {

  private static func components(from hex: UInt) -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
    (
      red: CGFloat((hex >> 16) & 0xFF) / 255.0,
      green: CGFloat((hex >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hex & 0xFF) / 255.0
    )
  }

  private static func dynamic(light: UInt, dark: UInt, opacity: CGFloat = 1.0) -> Color {
    Color(
      uiColor: UIColor { traitCollection in
        let hex = traitCollection.userInterfaceStyle == .dark ? dark : light
        let value = components(from: hex)
        return UIColor(
          red: value.red,
          green: value.green,
          blue: value.blue,
          alpha: opacity
        )
      }
    )
  }

  init(hex: UInt, opacity: Double = 1.0) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255.0,
      green: Double((hex >> 8) & 0xFF) / 255.0,
      blue: Double(hex & 0xFF) / 255.0,
      opacity: opacity
    )
  }

  static let ecliptixBackground = dynamic(light: 0xFAFAFA, dark: 0x111111)
  static let ecliptixBackgroundSecondary = dynamic(light: 0xF5F5F5, dark: 0x161616)
  static let ecliptixSurface = dynamic(light: 0xFFFFFF, dark: 0x1A1A1A)
  static let ecliptixSurfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x1C1C1C)
  static let ecliptixPrimaryText = dynamic(light: 0x1F2328, dark: 0xD4D4D4)
  static let ecliptixSecondaryText = dynamic(light: 0x57606A, dark: 0x9DA5B4)
  static var ecliptixAccent: Color {
    let rawValue =
      UserDefaults.standard.string(forKey: "accent_color") ?? AccentColor.green.rawValue
    return (AccentColor(rawValue: rawValue) ?? .green).color
  }

  static let ecliptixDanger = dynamic(light: 0xCF222E, dark: 0xF87171)
  static let ecliptixSuccess = dynamic(light: 0x1A7F37, dark: 0x3FB950)
  static let ecliptixOnlineIndicator = dynamic(light: 0x22C55E, dark: 0x22C55E)
  static let ecliptixWarning = dynamic(light: 0x9A6700, dark: 0xFBBF24)
  static let ecliptixStroke = dynamic(light: 0x0F172A, dark: 0xFFFFFF, opacity: 0.12)
  static let ecliptixMutedStroke = dynamic(light: 0x0F172A, dark: 0xFFFFFF, opacity: 0.08)
  static let ecliptixDisabled = dynamic(light: 0xC9D1D9, dark: 0x3A3A40)
  static let ecliptixPrimaryButton = dynamic(light: 0x111111, dark: 0xF3F4F6)
  static let ecliptixPrimaryButtonText = dynamic(light: 0xFFFFFF, dark: 0x111111)
  static let ecliptixSubtleButtonText = dynamic(light: 0x111111, dark: 0xE5E7EB)
  static let ecliptixPrimaryButtonGradientStart = dynamic(light: 0x111827, dark: 0xE5E7EB)
  static let ecliptixPrimaryButtonGradientEnd = dynamic(light: 0x1F2937, dark: 0xF3F4F6)
  static let ecliptixSecondaryButton = dynamic(light: 0xF3F4F6, dark: 0x2A2A2E)
  static let ecliptixSecondaryButtonText = dynamic(light: 0x111827, dark: 0xE5E7EB)
  static let ecliptixGlowOrange = Color(hex: 0xF97316)
  static let ecliptixGlowPink = Color(hex: 0xEC4899)
  static let ecliptixGlowPurple = Color(hex: 0xA855F7)
  static let ecliptixEppBadgeBg = dynamic(light: 0xF3E8FF, dark: 0x2D1B69)
  static let ecliptixOnlineBadgeBg = dynamic(light: 0xECFDF5, dark: 0x0D2818)
  static let ecliptixOnlineBadgeBorder = dynamic(light: 0xBBF7D0, dark: 0x166534)
  static let ecliptixOfflineBadgeBg = dynamic(light: 0xF3F4F6, dark: 0x27272A)
  static let ecliptixTertiaryText = dynamic(light: 0x666666, dark: 0x8B8B8B)
  static let ecliptixIndicatorInactive = dynamic(light: 0xE0E0E0, dark: 0x3A3A3A)
  static let ecliptixGlassTint = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, opacity: 0.08)
  static let ecliptixGlassBorder = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, opacity: 0.12)
  static let ecliptixGlassHighlight = dynamic(light: 0xFFFFFF, dark: 0xFFFFFF, opacity: 0.18)

  static func themedBackground(for theme: AppTheme) -> Color {
    switch theme {
    case .midnight: Color(hex: 0x000000)
    case .frost: Color(hex: 0xF0F4FF)
    default: ecliptixBackground
    }
  }

  static func themedSurface(for theme: AppTheme) -> Color {
    switch theme {
    case .midnight: Color(hex: 0x0A0A0A)
    case .frost: Color(hex: 0xF8FAFF)
    default: ecliptixSurface
    }
  }
}

struct EcliptixScreenBackground: View {

  @AppStorage("app_theme") private var themeRaw: String = AppTheme.light.rawValue
  private var theme: AppTheme { AppTheme(rawValue: themeRaw) ?? .light }
  var body: some View {
    Color.themedBackground(for: theme).ignoresSafeArea()
  }
}

struct EcliptixInputModifier: ViewModifier {

  var cornerRadius: CGFloat = 14

  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color.ecliptixSurfaceElevated)
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(Color.ecliptixMutedStroke, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
      .foregroundColor(.ecliptixPrimaryText)
  }
}

extension View {

  func ecliptixInput(cornerRadius: CGFloat = 14) -> some View {
    modifier(EcliptixInputModifier(cornerRadius: cornerRadius))
  }
}

extension Font {

  static func geist(_ weight: GeistWeight, size: CGFloat, relativeTo style: Font.TextStyle = .body)
    -> Font
  {
    .custom(weight.postScriptName, size: size, relativeTo: style)
  }

  static let geistLargeTitle = geist(.bold, size: 34, relativeTo: .largeTitle)
  static let geistTitle = geist(.semiBold, size: 28, relativeTo: .title)
  static let geistTitle2 = geist(.semiBold, size: 22, relativeTo: .title2)
  static let geistTitle3 = geist(.semiBold, size: 20, relativeTo: .title3)
  static let geistHeadline = geist(.semiBold, size: 17, relativeTo: .headline)
  static let geistBody = geist(.regular, size: 17, relativeTo: .body)
  static let geistCallout = geist(.regular, size: 16, relativeTo: .callout)
  static let geistSubheadline = geist(.regular, size: 15, relativeTo: .subheadline)
  static let geistFootnote = geist(.regular, size: 13, relativeTo: .footnote)
  static let geistCaption = geist(.regular, size: 12, relativeTo: .caption)
  static let geistCaption2 = geist(.regular, size: 11, relativeTo: .caption2)
}

enum GeistWeight {
  case light, regular, medium, semiBold, bold
  var postScriptName: String {
    switch self {
    case .light: "Geist-Light"
    case .regular: "Geist-Regular"
    case .medium: "Geist-Medium"
    case .semiBold: "Geist-SemiBold"
    case .bold: "Geist-Bold"
    }
  }
}
