// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct GroupAvatarView: View {

  let title: String
  let avatarUrl: String?
  var size: CGFloat = 52

  var body: some View {
    ZStack {
      Circle()
        .fill(
          LinearGradient(
            colors: [.ecliptixAccent, .ecliptixAccent.opacity(0.7)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .frame(width: size, height: size)

      Text(initials)
        .font(.geist(.semiBold, size: size * 0.35))
        .foregroundStyle(.white)
    }
  }

  private var initials: String {
    title.initials
  }
}
