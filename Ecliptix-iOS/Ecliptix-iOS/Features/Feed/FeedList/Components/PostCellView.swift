// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PostCellView: View {

  let post: PostDisplayItem
  let onLike: () -> Void
  let onRepost: () -> Void
  let onReply: () -> Void
  let onQuote: () -> Void
  let onShare: () -> Void
  let onBookmark: () -> Void
  let onAuthorTap: () -> Void
  let onPostTap: () -> Void
  var showThreadLine: Bool = false

  private var displayPost: PostDisplayItem {
    if post.postType == .repost, let reposted = post.repostedPost {
      return PostDisplayItem(
        id: reposted.id,
        author: reposted.author,
        postType: .original,
        textContent: reposted.textContent,
        media: reposted.media,
        quotedPost: nil,
        repostedPost: nil,
        metrics: reposted.metrics,
        interaction: reposted.interaction,
        createdAt: reposted.createdAt,
        editedAt: nil,
        isDeleted: false,
        parentPostId: nil,
        replyDepth: 0
      )
    }
    return post
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if post.postType == .repost {
        HStack(spacing: 4) {
          Image(systemName: "arrow.2.squarepath")
            .font(.system(size: 12))
          Text("\(post.author.displayName) reposted")
            .font(.geistCaption)
        }
        .foregroundStyle(Color.ecliptixSecondaryText)
        .padding(.leading, 52)
        .padding(.bottom, 4)
      }

      HStack(alignment: .top, spacing: 12) {
        VStack(spacing: 0) {
          PostAvatarView(
            displayName: displayPost.author.displayName,
            avatarUrl: displayPost.author.avatarUrl,
            isVerified: displayPost.author.isVerified,
            size: 40,
            onTap: onAuthorTap
          )

          if showThreadLine {
            Rectangle()
              .fill(Color.ecliptixMutedStroke)
              .frame(width: 2)
              .frame(maxHeight: .infinity)
              .padding(.vertical, 4)
          }
        }

        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 4) {
            Text(displayPost.author.displayName)
              .font(.geist(.semiBold, size: 15))
              .foregroundStyle(Color.ecliptixPrimaryText)
              .lineLimit(1)

            Text("@\(displayPost.author.profileName)")
              .font(.geistFootnote)
              .foregroundStyle(Color.ecliptixSecondaryText)
              .lineLimit(1)

            Text("\u{00B7}")
              .foregroundStyle(Color.ecliptixSecondaryText)

            RelativeTimestamp(date: displayPost.createdAt)
          }

          if !displayPost.textContent.isEmpty {
            Text(displayPost.textContent)
              .font(.geistBody)
              .foregroundStyle(Color.ecliptixPrimaryText)
              .multilineTextAlignment(.leading)
          }

          if let quoted = displayPost.quotedPost {
            QuotedPostCard(quotedPost: quoted)
              .padding(.top, 4)
          }

          PostMetricsBar(
            metrics: displayPost.metrics,
            interaction: displayPost.interaction,
            onReply: onReply,
            onRepost: onRepost,
            onLike: onLike,
            onShare: onShare,
            onBookmark: onBookmark
          )
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: onPostTap)
    .accessibilityElement(children: .combine)
  }
}
