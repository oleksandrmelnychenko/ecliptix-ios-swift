// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct TypingIndicatorView: View {

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let dotSize: CGFloat = 5

  var body: some View {
    HStack(spacing: 3) {
      if reduceMotion {
        ForEach(0..<3, id: \.self) { _ in
          Circle()
            .fill(Color.ecliptixSecondaryText)
            .frame(width: dotSize, height: dotSize)
            .opacity(0.6)
        }
      } else {
        PhaseAnimator([0, 1, 2]) { phase in
          HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
              Circle()
                .fill(Color.ecliptixSecondaryText)
                .frame(width: dotSize, height: dotSize)
                .scaleEffect(phase == index ? 1.3 : 0.7)
                .opacity(phase == index ? 1.0 : 0.4)
            }
          }
        } animation: { _ in
          .spring(.bouncy(duration: 0.4))
        }
      }
    }
    .frame(height: 12)
  }
}
