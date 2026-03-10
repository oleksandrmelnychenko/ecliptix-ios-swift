// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PinDotView: View {

  let filledCount: Int
  let totalDigits: Int
  let hasError: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(filledCount: Int, totalDigits: Int = 4, hasError: Bool = false) {
    self.filledCount = filledCount
    self.totalDigits = totalDigits
    self.hasError = hasError
  }

  var body: some View {
    HStack(spacing: 20) {
      ForEach(0..<totalDigits, id: \.self) { index in
        Circle()
          .fill(dotFill(for: index))
          .frame(width: 18, height: 18)
          .overlay(
            Circle()
              .stroke(dotStroke(for: index), lineWidth: index < filledCount ? 0 : 1.5)
          )
          .scaleEffect(index < filledCount ? 1.15 : 1.0)
          .animation(.ecliptixBouncy, value: filledCount)
      }
    }
    .keyframeAnimator(
      initialValue: CGFloat.zero,
      trigger: hasError
    ) { [reduceMotion] content, value in
      content.offset(x: reduceMotion ? 0 : value)
    } keyframes: { _ in
      SpringKeyframe(10, duration: 0.08, spring: .bouncy)
      SpringKeyframe(-8, duration: 0.08, spring: .bouncy)
      SpringKeyframe(5, duration: 0.08, spring: .bouncy)
      SpringKeyframe(-3, duration: 0.08, spring: .bouncy)
      SpringKeyframe(0, duration: 0.1, spring: .bouncy)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(filledCount) of \(totalDigits) digits entered")
    .accessibilityValue(hasError ? String(localized: "Error") : "")
  }

  private func dotFill(for index: Int) -> Color {
    if hasError { return .ecliptixDanger }
    return index < filledCount ? .ecliptixAccent : .clear
  }

  private func dotStroke(for index: Int) -> Color {
    if hasError { return .ecliptixDanger.opacity(0.5) }
    return index < filledCount ? .clear : .ecliptixMutedStroke
  }
}
