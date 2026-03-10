// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension AppDependencies {

  @MainActor
  func makeFeedListViewModel() -> FeedListViewModel {
    FeedListViewModel(
      feedService: feedRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makePostDetailViewModel(postId: Data) -> PostDetailViewModel {
    PostDetailViewModel(
      feedService: feedRpcService,
      postId: postId,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeCreatePostViewModel(
    onPostCreated: @escaping () -> Void = {}
  ) -> CreatePostViewModel {
    CreatePostViewModel(
      feedService: feedRpcService,
      mode: .original,
      onPostCreated: onPostCreated,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeCreateReplyViewModel(
    parentPostId: Data,
    parentAuthorName: String,
    onPostCreated: @escaping () -> Void = {}
  ) -> CreatePostViewModel {
    CreatePostViewModel(
      feedService: feedRpcService,
      mode: .reply,
      replyToPostId: parentPostId,
      replyToAuthorName: parentAuthorName,
      onPostCreated: onPostCreated,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeCreateQuoteViewModel(
    quotedPostId: Data,
    onPostCreated: @escaping () -> Void = {}
  ) -> CreatePostViewModel {
    CreatePostViewModel(
      feedService: feedRpcService,
      mode: .quote,
      quotePostId: quotedPostId,
      onPostCreated: onPostCreated,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }
}
