// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

@Observable @MainActor
final class FeedListViewModel: Resettable {

  var forYouPosts: [PostDisplayItem] = []
  var followingPosts: [PostDisplayItem] = []
  var selectedFeedTab: FeedTimeline = .forYou
  var isLoading = false
  var isLoadingMore = false
  var hasMoreForYou = true
  var hasMoreFollowing = true
  var hasError = false
  var errorMessage = ""
  var hasNewPostsAvailable = false

  var currentPosts: [PostDisplayItem] {
    selectedFeedTab == .forYou ? forYouPosts : followingPosts
  }

  var currentHasMore: Bool {
    selectedFeedTab == .forYou ? hasMoreForYou : hasMoreFollowing
  }

  private let feedService: FeedRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  private var forYouCursor = ""
  private var followingCursor = ""

  init(
    feedService: FeedRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.feedService = feedService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadFeed() async {
    guard !isLoading else { return }
    isLoading = true
    hasError = false
    defer { isLoading = false }

    guard let identity = resolveIdentity() else {
      loadMockData()
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let currentTab = selectedFeedTab
    let feedType: ProtoFeedType = currentTab == .forYou ? .forYou : .following

    let result = await feedService.getFeed(
      accountId: accountId,
      membershipId: membershipId,
      feedType: feedType,
      pageSize: 20,
      cursor: "",
      connectId: connectId
    )

    switch result {
    case .ok(let response):
      let posts = response.posts.map { mapPost($0, currentMembershipId: membershipId) }
      if currentTab == .forYou {
        forYouPosts = posts
        forYouCursor = response.nextCursor
        hasMoreForYou = response.hasMore_p
      } else {
        followingPosts = posts
        followingCursor = response.nextCursor
        hasMoreFollowing = response.hasMore_p
      }
    case .err(let error):
      AppLogger.feed.warning("LoadFeed failed: \(error, privacy: .public)")
      loadMockData()
    }
  }

  func refreshFeed() async {
    if selectedFeedTab == .forYou {
      forYouCursor = ""
    } else {
      followingCursor = ""
    }
    await loadFeed()
  }

  func loadMorePosts() async {
    guard !isLoadingMore, currentHasMore else { return }
    isLoadingMore = true
    defer { isLoadingMore = false }

    guard let identity = resolveIdentity() else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.feed.error("LoadMorePosts: missing identity")
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let currentTab = selectedFeedTab
    let feedType: ProtoFeedType = currentTab == .forYou ? .forYou : .following
    let cursor = currentTab == .forYou ? forYouCursor : followingCursor

    guard !cursor.isEmpty else { return }

    let result = await feedService.getFeed(
      accountId: accountId,
      membershipId: membershipId,
      feedType: feedType,
      pageSize: 20,
      cursor: cursor,
      connectId: connectId
    )

    switch result {
    case .ok(let response):
      let newPosts = response.posts.map { mapPost($0, currentMembershipId: membershipId) }
      if currentTab == .forYou {
        forYouPosts.append(contentsOf: newPosts)
        forYouCursor = response.nextCursor
        hasMoreForYou = response.hasMore_p
      } else {
        followingPosts.append(contentsOf: newPosts)
        followingCursor = response.nextCursor
        hasMoreFollowing = response.hasMore_p
      }
    case .err(let error):
      AppLogger.feed.warning("LoadMorePosts failed: \(error, privacy: .public)")
    }
  }

  func toggleLike(_ postId: Data) async {
    guard let index = findPostIndex(postId) else { return }

    let wasLiked = currentPosts[index].interaction.liked
    mutateCurrentPost(at: index) { post in
      post.interaction.liked = !wasLiked
      post.metrics.likeCount += wasLiked ? -1 : 1
    }

    guard let identity = resolveIdentity() else {
      revertInteraction(postId: postId) { post in
        post.interaction.liked = wasLiked
        post.metrics.likeCount += wasLiked ? 1 : -1
      }
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await feedService.likePost(
      accountId: identity.accountId,
      membershipId: identity.membershipId,
      postId: postId,
      connectId: connectId
    )

    if case .err(let error) = result {
      AppLogger.feed.warning("ToggleLike failed: \(error, privacy: .public), reverting")
      revertInteraction(postId: postId) { post in
        post.interaction.liked = wasLiked
        post.metrics.likeCount += wasLiked ? 1 : -1
      }
    }
  }

  func toggleRepost(_ postId: Data) async {
    guard let index = findPostIndex(postId) else { return }

    let wasReposted = currentPosts[index].interaction.reposted
    mutateCurrentPost(at: index) { post in
      post.interaction.reposted = !wasReposted
      post.metrics.repostCount += wasReposted ? -1 : 1
    }

    guard let identity = resolveIdentity() else {
      revertInteraction(postId: postId) { post in
        post.interaction.reposted = wasReposted
        post.metrics.repostCount += wasReposted ? 1 : -1
      }
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await feedService.repost(
      accountId: identity.accountId,
      membershipId: identity.membershipId,
      postId: postId,
      connectId: connectId
    )

    if case .err(let error) = result {
      AppLogger.feed.warning("ToggleRepost failed: \(error, privacy: .public), reverting")
      revertInteraction(postId: postId) { post in
        post.interaction.reposted = wasReposted
        post.metrics.repostCount += wasReposted ? 1 : -1
      }
    }
  }

  func toggleBookmark(_ postId: Data) async {
    guard let index = findPostIndex(postId) else { return }

    let wasBookmarked = currentPosts[index].interaction.bookmarked
    mutateCurrentPost(at: index) { post in
      post.interaction.bookmarked = !wasBookmarked
      post.metrics.bookmarkCount += wasBookmarked ? -1 : 1
    }

    guard let identity = resolveIdentity() else {
      revertInteraction(postId: postId) { post in
        post.interaction.bookmarked = wasBookmarked
        post.metrics.bookmarkCount += wasBookmarked ? 1 : -1
      }
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await feedService.bookmarkPost(
      accountId: identity.accountId,
      membershipId: identity.membershipId,
      postId: postId,
      connectId: connectId
    )

    if case .err(let error) = result {
      AppLogger.feed.warning("ToggleBookmark failed: \(error, privacy: .public), reverting")
      revertInteraction(postId: postId) { post in
        post.interaction.bookmarked = wasBookmarked
        post.metrics.bookmarkCount += wasBookmarked ? 1 : -1
      }
    }
  }

  func deletePost(_ postId: Data) async {
    guard let identity = resolveIdentity() else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.feed.error("DeletePost: missing identity")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    if selectedFeedTab == .forYou {
      forYouPosts.removeAll { $0.id == postId }
    } else {
      followingPosts.removeAll { $0.id == postId }
    }

    let result = await feedService.deletePost(
      accountId: identity.accountId,
      membershipId: identity.membershipId,
      postId: postId,
      connectId: connectId
    )

    if case .err(let error) = result {
      AppLogger.feed.error("DeletePost failed: \(error, privacy: .public)")
      await refreshFeed()
    }
  }

  func resetState() {
    forYouPosts = []
    followingPosts = []
    selectedFeedTab = .forYou
    isLoading = false
    isLoadingMore = false
    hasMoreForYou = true
    hasMoreFollowing = true
    hasError = false
    errorMessage = ""
    hasNewPostsAvailable = false
    forYouCursor = ""
    followingCursor = ""
  }

  private func findPostIndex(_ postId: Data) -> Int? {
    currentPosts.firstIndex(where: { $0.id == postId })
  }

  private func mutateCurrentPost(at index: Int, _ mutation: (inout PostDisplayItem) -> Void) {
    if selectedFeedTab == .forYou {
      mutation(&forYouPosts[index])
    } else {
      mutation(&followingPosts[index])
    }
  }

  private func revertInteraction(postId: Data, _ revert: (inout PostDisplayItem) -> Void) {
    if let idx = findPostIndex(postId) {
      mutateCurrentPost(at: idx, revert)
    }
  }

  private func resolveIdentity() -> (accountId: Data, membershipId: Data)? {
    guard let currentAccountId,
      let membershipUUID = settingsProvider()?.membership?.membershipId
    else {
      return nil
    }
    return (accountId: currentAccountId, membershipId: membershipUUID.protobufBytes)
  }

  private func mapPost(_ proto: ProtoPost, currentMembershipId: Data) -> PostDisplayItem {
    .from(proto: proto, currentMembershipId: currentMembershipId)
  }

  #if DEBUG

    private func loadMockData() {
      let mockAuthor = PostDisplayItem.AuthorDisplay(
        membershipId: Data(repeating: 1, count: 16),
        accountId: Data(repeating: 1, count: 16),
        displayName: "Oleksandr",
        profileName: "oleksandr",
        avatarUrl: nil,
        isVerified: true
      )
      let mockAuthor2 = PostDisplayItem.AuthorDisplay(
        membershipId: Data(repeating: 2, count: 16),
        accountId: Data(repeating: 2, count: 16),
        displayName: "Tech Store UA",
        profileName: "techstore",
        avatarUrl: nil,
        isVerified: true
      )
      let now = Date()
      forYouPosts = [
        PostDisplayItem(
          id: Data(repeating: 10, count: 16),
          author: mockAuthor,
          postType: .original,
          textContent:
            "Building something amazing with Ecliptix! The future of secure messaging is here.",
          media: [],
          quotedPost: nil,
          repostedPost: nil,
          metrics: PostDisplayItem.MetricsDisplay(
            replyCount: 12, repostCount: 5, likeCount: 142, quoteCount: 3, viewCount: 1200,
            bookmarkCount: 8),
          interaction: PostDisplayItem.InteractionDisplay(
            liked: false, reposted: false, bookmarked: false),
          createdAt: now.addingTimeInterval(-3600),
          editedAt: nil,
          isDeleted: false,
          parentPostId: nil,
          replyDepth: 0
        ),
        PostDisplayItem(
          id: Data(repeating: 11, count: 16),
          author: mockAuthor2,
          postType: .original,
          textContent: "New AirPods Pro available now! Free delivery across Ukraine.",
          media: [],
          quotedPost: nil,
          repostedPost: nil,
          metrics: PostDisplayItem.MetricsDisplay(
            replyCount: 28, repostCount: 15, likeCount: 384, quoteCount: 7, viewCount: 5400,
            bookmarkCount: 42),
          interaction: PostDisplayItem.InteractionDisplay(
            liked: true, reposted: false, bookmarked: true),
          createdAt: now.addingTimeInterval(-7200),
          editedAt: nil,
          isDeleted: false,
          parentPostId: nil,
          replyDepth: 0
        ),
        PostDisplayItem(
          id: Data(repeating: 12, count: 16),
          author: mockAuthor,
          postType: .original,
          textContent:
            "Just deployed the new feed feature. Twitter-style posts are coming to Ecliptix!",
          media: [],
          quotedPost: nil,
          repostedPost: nil,
          metrics: PostDisplayItem.MetricsDisplay(
            replyCount: 4, repostCount: 2, likeCount: 67, quoteCount: 1, viewCount: 890,
            bookmarkCount: 3),
          interaction: PostDisplayItem.InteractionDisplay(
            liked: false, reposted: false, bookmarked: false),
          createdAt: now.addingTimeInterval(-14400),
          editedAt: nil,
          isDeleted: false,
          parentPostId: nil,
          replyDepth: 0
        ),
      ]
      followingPosts = forYouPosts
    }
  #else

    private func loadMockData() {
      hasError = true
      errorMessage = String(localized: "Failed to load feed")
    }
  #endif
}
