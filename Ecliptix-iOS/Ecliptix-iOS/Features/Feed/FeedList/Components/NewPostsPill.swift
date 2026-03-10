// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct NewPostsPill: View {

  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      HStack(spacing: 6) {
        Image(systemName: "arrow.up")
          .font(.system(size: 12, weight: .semibold))
        Text(String(localized: "New posts"))
          .font(.geist(.semiBold, size: 13))
      }
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .background(Color.ecliptixAccent)
      .clipShape(Capsule())
      .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("Load new posts"))
  }
}
