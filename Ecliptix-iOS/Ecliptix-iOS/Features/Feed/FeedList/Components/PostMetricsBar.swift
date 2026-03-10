// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PostMetricsBar: View {

  let metrics: PostDisplayItem.MetricsDisplay
  let interaction: PostDisplayItem.InteractionDisplay
  let onReply: () -> Void
  let onRepost: () -> Void
  let onLike: () -> Void
  let onShare: () -> Void
  let onBookmark: () -> Void

  var body: some View {
    HStack(spacing: 0) {
      metricButton(
        icon: "bubble.right",
        count: metrics.replyCount,
        isActive: false,
        activeColor: .ecliptixAccent,
        action: onReply
      )
      .accessibilityLabel(Text("\(metrics.replyCount) replies"))

      Spacer()

      metricButton(
        icon: "arrow.2.squarepath",
        count: metrics.repostCount,
        isActive: interaction.reposted,
        activeColor: .ecliptixSuccess,
        action: onRepost
      )
      .accessibilityLabel(Text(interaction.reposted ? "Unrepost" : "Repost"))

      Spacer()

      metricButton(
        icon: interaction.liked ? "heart.fill" : "heart",
        count: metrics.likeCount,
        isActive: interaction.liked,
        activeColor: .ecliptixDanger,
        action: onLike
      )
      .accessibilityLabel(
        Text(
          interaction.liked
            ? "Unlike, \(metrics.likeCount) likes" : "Like, \(metrics.likeCount) likes"))

      Spacer()

      metricButton(
        icon: "square.and.arrow.up",
        count: 0,
        isActive: false,
        activeColor: .ecliptixAccent,
        action: onShare
      )
      .accessibilityLabel(Text("Share"))

      Spacer()

      metricButton(
        icon: interaction.bookmarked ? "bookmark.fill" : "bookmark",
        count: 0,
        isActive: interaction.bookmarked,
        activeColor: .ecliptixAccent,
        action: onBookmark
      )
      .accessibilityLabel(Text(interaction.bookmarked ? "Remove bookmark" : "Bookmark"))
    }
    .padding(.top, 8)
  }

  @ViewBuilder
  private func metricButton(
    icon: String,
    count: Int64,
    isActive: Bool,
    activeColor: Color,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.system(size: 14))
          .foregroundStyle(isActive ? activeColor : Color.ecliptixSecondaryText)
          .scaleEffect(isActive ? 1.1 : 1.0)
          .animation(.ecliptixBouncy, value: isActive)

        if count > 0 {
          Text(formattedCount(count))
            .font(.geistCaption)
            .foregroundStyle(isActive ? activeColor : Color.ecliptixSecondaryText)
        }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func formattedCount(_ count: Int64) -> String {
    if count >= 1_000_000 {
      return String(format: "%.1fM", Double(count) / 1_000_000)
    } else if count >= 1_000 {
      return String(format: "%.1fK", Double(count) / 1_000)
    }
    return "\(count)"
  }
}
