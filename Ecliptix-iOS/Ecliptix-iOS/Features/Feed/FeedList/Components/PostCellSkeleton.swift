// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PostCellSkeleton: View {

  @State private var isAnimating = false

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Circle()
        .fill(Color.ecliptixMutedStroke)
        .frame(width: 40, height: 40)

      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.ecliptixMutedStroke)
            .frame(width: 100, height: 14)

          RoundedRectangle(cornerRadius: 4)
            .fill(Color.ecliptixMutedStroke)
            .frame(width: 60, height: 14)
        }

        RoundedRectangle(cornerRadius: 4)
          .fill(Color.ecliptixMutedStroke)
          .frame(height: 14)

        RoundedRectangle(cornerRadius: 4)
          .fill(Color.ecliptixMutedStroke)
          .frame(width: 200, height: 14)

        HStack(spacing: 24) {
          ForEach(0..<4, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 4)
              .fill(Color.ecliptixMutedStroke)
              .frame(width: 30, height: 12)
          }
        }
        .padding(.top, 4)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .opacity(isAnimating ? 0.5 : 1.0)
    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
    .onAppear { isAnimating = true }
    .onDisappear { isAnimating = false }
  }
}
