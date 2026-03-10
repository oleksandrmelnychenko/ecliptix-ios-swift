// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PostAvatarView: View {

  let displayName: String
  let avatarUrl: String?
  let isVerified: Bool
  var size: CGFloat = 40
  var onTap: (() -> Void)?

  var body: some View {
    Button {
      onTap?()
    } label: {
      ZStack(alignment: .bottomTrailing) {
        if let avatarUrl, let url = URL(string: avatarUrl) {
          AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
          } placeholder: {
            initialsView
          }
          .frame(width: size, height: size)
          .clipShape(Circle())
        } else {
          initialsView
        }

        if isVerified {
          Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size * 0.3))
            .foregroundStyle(.white, Color.ecliptixAccent)
            .offset(x: 2, y: 2)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("\(displayName) avatar"))
  }

  private var initialsView: some View {
    Circle()
      .fill(Color.ecliptixAccent.opacity(0.15))
      .frame(width: size, height: size)
      .overlay {
        Text(displayName.initials)
          .font(.geist(.semiBold, size: size * 0.4))
          .foregroundStyle(Color.ecliptixAccent)
      }
  }
}
