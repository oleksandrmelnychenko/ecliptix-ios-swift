// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct FeedListView: View {

  @State private var viewModel: FeedListViewModel
  var onNavigate: (FeedNavigationDestination) -> Void

  init(viewModel: FeedListViewModel, onNavigate: @escaping (FeedNavigationDestination) -> Void) {
    self._viewModel = State(initialValue: viewModel)
    self.onNavigate = onNavigate
  }

  var body: some View {
    ZStack(alignment: .top) {
      EcliptixScreenBackground()

      VStack(spacing: 0) {
        FeedTabSelector(selectedTab: $viewModel.selectedFeedTab)

        if viewModel.isLoading && viewModel.currentPosts.isEmpty {
          feedSkeleton
        } else if viewModel.currentPosts.isEmpty {
          emptyFeedState
        } else {
          feedScrollView
        }
      }

      if viewModel.hasNewPostsAvailable {
        NewPostsPill(onTap: {
          Task { await viewModel.refreshFeed() }
          viewModel.hasNewPostsAvailable = false
        })
        .transition(.move(edge: .top).combined(with: .opacity))
        .padding(.top, 52)
      }
    }
    .navigationTitle(String(localized: "Feed"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          onNavigate(.createPost)
        } label: {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 22))
            .foregroundStyle(Color.ecliptixAccent)
        }
        .accessibilityLabel(Text("Create post"))
      }
    }
    .refreshable { await viewModel.refreshFeed() }
    .task { await viewModel.loadFeed() }
    .onChange(of: viewModel.selectedFeedTab) { _, _ in
      Task { await viewModel.loadFeed() }
    }
  }

  private var feedSkeleton: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(0..<5, id: \.self) { _ in
          PostCellSkeleton()
          Divider()
            .foregroundStyle(Color.ecliptixMutedStroke)
        }
      }
    }
  }

  private var emptyFeedState: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "text.bubble")
        .font(.system(size: 48))
        .foregroundStyle(Color.ecliptixTertiaryText)
        .accessibilityHidden(true)
      Text(String(localized: "No posts yet"))
        .font(.geistTitle3)
        .foregroundStyle(Color.ecliptixPrimaryText)
      Text(String(localized: "Follow people to see their posts here"))
        .font(.geistSubheadline)
        .foregroundStyle(Color.ecliptixSecondaryText)
        .multilineTextAlignment(.center)
      Spacer()
    }
    .padding(.horizontal, 32)
  }

  private var feedScrollView: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(viewModel.currentPosts) { post in
          PostCellView(
            post: post,
            onLike: { Task { await viewModel.toggleLike(post.id) } },
            onRepost: { Task { await viewModel.toggleRepost(post.id) } },
            onReply: {
              onNavigate(
                .createReply(parentPostId: post.id, parentAuthorName: post.author.displayName))
            },
            onQuote: { onNavigate(.createQuote(quotedPostId: post.id)) },
            onShare: {},
            onBookmark: { Task { await viewModel.toggleBookmark(post.id) } },
            onAuthorTap: { onNavigate(.profile(membershipId: post.author.membershipId)) },
            onPostTap: { onNavigate(.postThread(postId: post.id)) }
          )

          Divider()
            .foregroundStyle(Color.ecliptixMutedStroke)
        }

        if viewModel.isLoadingMore {
          ProgressView()
            .padding()
        } else if viewModel.currentHasMore {
          Color.clear
            .frame(height: 1)
            .onAppear {
              Task { await viewModel.loadMorePosts() }
            }
        }
      }
    }
  }
}
