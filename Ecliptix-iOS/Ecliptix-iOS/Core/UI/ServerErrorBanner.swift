// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ServerErrorBanner: View {

  let message: String

  var body: some View {
    if !message.isEmpty {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.geist(.medium, size: 16))
          .foregroundColor(.ecliptixDanger)
          .accessibilityHidden(true)
        Text(message)
          .font(.geistFootnote)
          .foregroundColor(.ecliptixDanger)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(12)
      .background {
        RoundedRectangle(cornerRadius: 10)
          .fill(.ultraThinMaterial)
          .overlay(
            RoundedRectangle(cornerRadius: 10)
              .fill(Color.ecliptixDanger.opacity(0.06))
          )
      }
      .overlay(
        RoundedRectangle(cornerRadius: 10)
          .stroke(Color.ecliptixDanger.opacity(0.15), lineWidth: 0.5)
      )
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text("Error: \(message)"))
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }
}
