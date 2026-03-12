// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct QuotedPostCard: View {

  let quotedPost: PostDisplayItem.QuotedPostDisplay

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text(quotedPost.author.displayName)
          .font(.geist(.semiBold, size: 13))
          .foregroundStyle(Color.ecliptixPrimaryText)

        Text("@\(quotedPost.author.handle)")
          .font(.geistCaption)
          .foregroundStyle(Color.ecliptixSecondaryText)

        Text("\u{00B7}")
          .foregroundStyle(Color.ecliptixSecondaryText)

        RelativeTimestamp(date: quotedPost.createdAt)
      }
      .lineLimit(1)

      if !quotedPost.textContent.isEmpty {
        Text(quotedPost.textContent)
          .font(.geistSubheadline)
          .foregroundStyle(Color.ecliptixPrimaryText)
          .lineLimit(3)
      }
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.ecliptixBackgroundSecondary)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(Color.ecliptixStroke, lineWidth: 1)
    }
  }
}
