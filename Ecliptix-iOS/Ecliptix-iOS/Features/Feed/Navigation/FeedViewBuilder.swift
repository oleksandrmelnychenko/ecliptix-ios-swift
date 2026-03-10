// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

@MainActor
enum FeedViewBuilder {

  @ViewBuilder
  static func destination(
    for destination: FeedNavigationDestination,
    coordinator: AppCoordinator,
    path: Binding<[FeedNavigationDestination]>
  ) -> some View {
    switch destination {
    case .postDetail(let postId):
      PostDetailView(
        viewModel: coordinator.dependencies.makePostDetailViewModel(postId: postId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    case .createPost:
      CreatePostView(
        viewModel: coordinator.dependencies.makeCreatePostViewModel(
          onPostCreated: { path.wrappedValue.removeLast() }
        )
      )
    case .createReply(let parentPostId, let parentAuthorName):
      CreatePostView(
        viewModel: coordinator.dependencies.makeCreateReplyViewModel(
          parentPostId: parentPostId,
          parentAuthorName: parentAuthorName,
          onPostCreated: { path.wrappedValue.removeLast() }
        )
      )
    case .createQuote(let quotedPostId):
      CreatePostView(
        viewModel: coordinator.dependencies.makeCreateQuoteViewModel(
          quotedPostId: quotedPostId,
          onPostCreated: { path.wrappedValue.removeLast() }
        )
      )
    case .userProfile(let membershipId):
      UserProfileView(
        viewModel: coordinator.dependencies.makeUserProfileViewModel(membershipId: membershipId),
        onSendMessage: { _ in }
      )
    case .postThread(let postId):
      PostDetailView(
        viewModel: coordinator.dependencies.makePostDetailViewModel(postId: postId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    }
  }
}
