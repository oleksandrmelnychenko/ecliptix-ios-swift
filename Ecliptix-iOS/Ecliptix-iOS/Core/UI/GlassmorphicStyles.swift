// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

enum GlassIntensity {
  case subtle
  case regular
  case prominent

  var materialOpacity: Double {
    switch self {
    case .subtle: 0.6
    case .regular: 0.8
    case .prominent: 0.92
    }
  }

  var borderHighlight: Double {
    switch self {
    case .subtle: 0.08
    case .regular: 0.15
    case .prominent: 0.2
    }
  }

  var borderBase: Double {
    switch self {
    case .subtle: 0.03
    case .regular: 0.06
    case .prominent: 0.08
    }
  }

  var shadowOpacity: Double {
    switch self {
    case .subtle: 0.05
    case .regular: 0.12
    case .prominent: 0.2
    }
  }

  var shadowRadius: CGFloat {
    switch self {
    case .subtle: 4
    case .regular: 10
    case .prominent: 20
    }
  }

  var shadowY: CGFloat {
    switch self {
    case .subtle: 1
    case .regular: 4
    case .prominent: 6
    }
  }
}

struct GlassmorphicModifier: ViewModifier {

  var cornerRadius: CGFloat = 16
  var intensity: GlassIntensity = .regular

  func body(content: Content) -> some View {
    content
      .background(
        RoundedRectangle(cornerRadius: cornerRadius)
          .fill(.ultraThinMaterial)
          .opacity(intensity.materialOpacity)
      )
      .overlay(
        RoundedRectangle(cornerRadius: cornerRadius)
          .stroke(
            LinearGradient(
              colors: [
                Color.white.opacity(intensity.borderHighlight),
                Color.white.opacity(intensity.borderBase),
              ],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ),
            lineWidth: 0.5
          )
      )
      .shadow(
        color: .black.opacity(intensity.shadowOpacity),
        radius: intensity.shadowRadius,
        y: intensity.shadowY
      )
      .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
  }
}

struct GlassCardModifier: ViewModifier {

  var cornerRadius: CGFloat = 16
  var padding: CGFloat = 16
  var intensity: GlassIntensity = .regular

  func body(content: Content) -> some View {
    content
      .padding(padding)
      .modifier(
        GlassmorphicModifier(
          cornerRadius: cornerRadius,
          intensity: intensity
        ))
  }
}

struct GlassButtonStyle: ButtonStyle {

  var cornerRadius: CGFloat = 12
  var intensity: GlassIntensity = .regular

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .modifier(
        GlassmorphicModifier(
          cornerRadius: cornerRadius,
          intensity: intensity
        )
      )
      .opacity(configuration.isPressed ? 0.85 : 1.0)
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
      .animation(.ecliptixSnappy, value: configuration.isPressed)
  }
}

extension View {

  func glassmorphic(
    cornerRadius: CGFloat = 16,
    intensity: GlassIntensity = .regular
  ) -> some View {
    modifier(
      GlassmorphicModifier(
        cornerRadius: cornerRadius,
        intensity: intensity
      ))
  }

  func glassCard(
    cornerRadius: CGFloat = 16,
    padding: CGFloat = 16,
    intensity: GlassIntensity = .regular
  ) -> some View {
    modifier(
      GlassCardModifier(
        cornerRadius: cornerRadius,
        padding: padding,
        intensity: intensity
      ))
  }
}

extension Animation {

  static let ecliptixSnappy: Animation = .spring(.snappy(duration: 0.2))

  static let ecliptixBouncy: Animation = .spring(.bouncy(duration: 0.3))

  static let ecliptixSmooth: Animation = .spring(.smooth(duration: 0.35))
}
