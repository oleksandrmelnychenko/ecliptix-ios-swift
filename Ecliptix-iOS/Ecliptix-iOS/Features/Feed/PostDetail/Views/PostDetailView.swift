// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PostDetailView: View {

  @State var viewModel: PostDetailViewModel
  var onNavigate: (FeedNavigationDestination) -> Void

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      if viewModel.isLoading && viewModel.thread == nil {
        ProgressView()
      } else if let thread = viewModel.thread {
        threadContent(thread)
      }
    }
    .navigationTitle(String(localized: "Post"))
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.loadThread() }
  }

  @ViewBuilder
  private func threadContent(_ thread: ThreadDisplayData) -> some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(thread.ancestorChain) { ancestor in
          PostCellView(
            post: ancestor,
            onLike: { Task { await viewModel.toggleLike(ancestor.id) } },
            onRepost: { Task { await viewModel.toggleRepost(ancestor.id) } },
            onReply: {
              onNavigate(
                .createReply(
                  parentPostId: ancestor.id, parentAuthorName: ancestor.author.displayName))
            },
            onQuote: { onNavigate(.createQuote(quotedPostId: ancestor.id)) },
            onShare: {},
            onBookmark: {},
            onAuthorTap: { onNavigate(.userProfile(membershipId: ancestor.author.membershipId)) },
            onPostTap: { onNavigate(.postThread(postId: ancestor.id)) },
            showThreadLine: true
          )
        }

        focalPostView(thread.focalPost)

        Divider()
          .foregroundStyle(Color.ecliptixMutedStroke)

        ForEach(thread.replies) { reply in
          PostCellView(
            post: reply,
            onLike: { Task { await viewModel.toggleLike(reply.id) } },
            onRepost: { Task { await viewModel.toggleRepost(reply.id) } },
            onReply: {
              onNavigate(
                .createReply(parentPostId: reply.id, parentAuthorName: reply.author.displayName))
            },
            onQuote: { onNavigate(.createQuote(quotedPostId: reply.id)) },
            onShare: {},
            onBookmark: {},
            onAuthorTap: { onNavigate(.userProfile(membershipId: reply.author.membershipId)) },
            onPostTap: { onNavigate(.postThread(postId: reply.id)) }
          )

          Divider()
            .foregroundStyle(Color.ecliptixMutedStroke)
        }

        if viewModel.isLoadingMoreReplies {
          ProgressView()
            .padding()
        } else if thread.hasMoreReplies {
          Color.clear
            .frame(height: 1)
            .onAppear {
              Task { await viewModel.loadMoreReplies() }
            }
        }
      }
    }
    .refreshable { await viewModel.loadThread() }
  }

  @ViewBuilder
  private func focalPostView(_ post: PostDisplayItem) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        PostAvatarView(
          displayName: post.author.displayName,
          avatarUrl: post.author.avatarUrl,
          isVerified: post.author.isVerified,
          size: 48,
          onTap: { onNavigate(.userProfile(membershipId: post.author.membershipId)) }
        )

        VStack(alignment: .leading, spacing: 2) {
          Text(post.author.displayName)
            .font(.geist(.semiBold, size: 16))
            .foregroundStyle(Color.ecliptixPrimaryText)
          Text("@\(post.author.profileName)")
            .font(.geistFootnote)
            .foregroundStyle(Color.ecliptixSecondaryText)
        }
      }

      if !post.textContent.isEmpty {
        Text(post.textContent)
          .font(.geist(.regular, size: 17))
          .foregroundStyle(Color.ecliptixPrimaryText)
      }

      Text(post.createdAt, format: .dateTime.month().day().year().hour().minute())
        .font(.geistFootnote)
        .foregroundStyle(Color.ecliptixSecondaryText)

      Divider()
        .foregroundStyle(Color.ecliptixMutedStroke)

      HStack(spacing: 16) {
        metricLabel(count: post.metrics.repostCount, label: String(localized: "Reposts"))
        metricLabel(count: post.metrics.quoteCount, label: String(localized: "Quotes"))
        metricLabel(count: post.metrics.likeCount, label: String(localized: "Likes"))
        metricLabel(count: post.metrics.bookmarkCount, label: String(localized: "Bookmarks"))
      }

      Divider()
        .foregroundStyle(Color.ecliptixMutedStroke)

      PostMetricsBar(
        metrics: post.metrics,
        interaction: post.interaction,
        onReply: {
          onNavigate(.createReply(parentPostId: post.id, parentAuthorName: post.author.displayName))
        },
        onRepost: { Task { await viewModel.toggleRepost(post.id) } },
        onLike: { Task { await viewModel.toggleLike(post.id) } },
        onShare: {},
        onBookmark: {}
      )
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  @ViewBuilder
  private func metricLabel(count: Int64, label: String) -> some View {
    if count > 0 {
      HStack(spacing: 4) {
        Text("\(count)")
          .font(.geist(.semiBold, size: 14))
          .foregroundStyle(Color.ecliptixPrimaryText)
        Text(label)
          .font(.geistFootnote)
          .foregroundStyle(Color.ecliptixSecondaryText)
      }
    }
  }
}
