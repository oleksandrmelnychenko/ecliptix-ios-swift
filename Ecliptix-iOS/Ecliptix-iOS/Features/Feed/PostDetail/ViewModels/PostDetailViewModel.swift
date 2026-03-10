// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

@Observable @MainActor
final class PostDetailViewModel: Resettable {

  var thread: ThreadDisplayData?
  var isLoading = false
  var isLoadingMoreReplies = false
  var hasError = false
  var errorMessage = ""

  private let feedService: FeedRpcService
  private let postId: Data
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  init(
    feedService: FeedRpcService,
    postId: Data,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.feedService = feedService
    self.postId = postId
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadThread() async {
    guard !isLoading else { return }
    isLoading = true
    hasError = false
    defer { isLoading = false }

    guard let identity = resolveIdentity() else {
      AppLogger.feed.warning("LoadThread: no membership, cannot load thread")
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await feedService.getPostThread(
      accountId: accountId,
      membershipId: membershipId,
      postId: postId,
      replyPageSize: 20,
      replyCursor: "",
      connectId: connectId
    )

    switch result {
    case .ok(let response):
      thread = ThreadDisplayData(
        ancestorChain: response.ancestorChain.map {
          mapPost($0, currentMembershipId: membershipId)
        },
        focalPost: mapPost(response.focalPost, currentMembershipId: membershipId),
        replies: response.replies.map { mapPost($0, currentMembershipId: membershipId) },
        hasMoreReplies: response.hasMoreReplies_p,
        nextReplyCursor: response.nextReplyCursor
      )
    case .err(let error):
      AppLogger.feed.warning("LoadThread failed: \(error, privacy: .public)")
      hasError = true
      errorMessage = String(localized: "Failed to load thread")
    }
  }

  func loadMoreReplies() async {
    guard !isLoadingMoreReplies,
      let thread,
      thread.hasMoreReplies,
      !thread.nextReplyCursor.isEmpty
    else { return }

    isLoadingMoreReplies = true
    defer { isLoadingMoreReplies = false }

    guard let identity = resolveIdentity() else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.feed.error("LoadMoreReplies: missing identity")
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await feedService.getPostThread(
      accountId: accountId,
      membershipId: membershipId,
      postId: postId,
      replyPageSize: 20,
      replyCursor: thread.nextReplyCursor,
      connectId: connectId
    )

    if case .ok(let response) = result {
      let newReplies = response.replies.map { mapPost($0, currentMembershipId: membershipId) }
      self.thread?.replies.append(contentsOf: newReplies)
      self.thread?.hasMoreReplies = response.hasMoreReplies_p
      self.thread?.nextReplyCursor = response.nextReplyCursor
    }
  }

  func toggleLike(_ postId: Data) async {
    guard var thread else { return }

    if thread.focalPost.id == postId {
      let wasLiked = thread.focalPost.interaction.liked
      thread.focalPost.interaction.liked = !wasLiked
      thread.focalPost.metrics.likeCount += wasLiked ? -1 : 1
      self.thread = thread
    } else if let idx = thread.replies.firstIndex(where: { $0.id == postId }) {
      let wasLiked = thread.replies[idx].interaction.liked
      thread.replies[idx].interaction.liked = !wasLiked
      thread.replies[idx].metrics.likeCount += wasLiked ? -1 : 1
      self.thread = thread
    }

    guard let identity = resolveIdentity() else {
      await loadThread()
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await feedService.likePost(
      accountId: accountId,
      membershipId: membershipId,
      postId: postId,
      connectId: connectId
    )

    if case .err(let error) = result {
      AppLogger.feed.warning("ToggleLike in thread failed: \(error, privacy: .public)")
      await loadThread()
    }
  }

  func toggleRepost(_ postId: Data) async {
    guard var thread else { return }

    if thread.focalPost.id == postId {
      let wasReposted = thread.focalPost.interaction.reposted
      thread.focalPost.interaction.reposted = !wasReposted
      thread.focalPost.metrics.repostCount += wasReposted ? -1 : 1
      self.thread = thread
    } else if let idx = thread.replies.firstIndex(where: { $0.id == postId }) {
      let wasReposted = thread.replies[idx].interaction.reposted
      thread.replies[idx].interaction.reposted = !wasReposted
      thread.replies[idx].metrics.repostCount += wasReposted ? -1 : 1
      self.thread = thread
    }

    guard let identity = resolveIdentity() else {
      await loadThread()
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await feedService.repost(
      accountId: accountId, membershipId: membershipId, postId: postId, connectId: connectId)
    if case .err(let error) = result {
      AppLogger.feed.warning("ToggleRepost in thread failed: \(error, privacy: .public)")
      await loadThread()
    }
  }

  func deletePost(_ postId: Data) async {
    guard let identity = resolveIdentity() else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.feed.error("DeletePost in thread: missing identity")
      return
    }

    let accountId = identity.accountId
    let membershipId = identity.membershipId
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await feedService.deletePost(
      accountId: accountId, membershipId: membershipId, postId: postId, connectId: connectId)

    switch result {
    case .ok:
      if var thread {
        thread.replies.removeAll { $0.id == postId }
        self.thread = thread
      }
    case .err(let error):
      AppLogger.feed.error("DeletePost in thread failed: \(error, privacy: .public)")
      hasError = true
      errorMessage = String(localized: "Failed to delete post. Please try again.")
    }
  }

  func resetState() {
    thread = nil
    isLoading = false
    isLoadingMoreReplies = false
    hasError = false
    errorMessage = ""
  }

  private func mapPost(_ proto: ProtoPost, currentMembershipId: Data) -> PostDisplayItem {
    .from(proto: proto, currentMembershipId: currentMembershipId)
  }

  private func resolveIdentity() -> (accountId: Data, membershipId: Data)? {
    guard let currentAccountId,
      let membershipUUID = settingsProvider()?.membership?.membershipId
    else {
      return nil
    }
    return (accountId: currentAccountId, membershipId: membershipUUID.protobufBytes)
  }

  #if DEBUG

    private func loadMockThread() {
      let mockAuthor = PostDisplayItem.AuthorDisplay(
        membershipId: Data(repeating: 1, count: 16),
        accountId: Data(repeating: 1, count: 16),
        displayName: "Oleksandr",
        profileName: "oleksandr",
        avatarUrl: nil,
        isVerified: true
      )
      let focalPost = PostDisplayItem(
        id: postId,
        author: mockAuthor,
        postType: .original,
        textContent:
          "This is a post in the thread view. Showing how threads work in Ecliptix feed.",
        media: [],
        quotedPost: nil,
        repostedPost: nil,
        metrics: PostDisplayItem.MetricsDisplay(
          replyCount: 3, repostCount: 1, likeCount: 24, quoteCount: 0, viewCount: 200,
          bookmarkCount: 2),
        interaction: PostDisplayItem.InteractionDisplay(
          liked: false, reposted: false, bookmarked: false),
        createdAt: Date().addingTimeInterval(-3600),
        editedAt: nil,
        isDeleted: false,
        parentPostId: nil,
        replyDepth: 0
      )
      thread = ThreadDisplayData(
        ancestorChain: [],
        focalPost: focalPost,
        replies: [],
        hasMoreReplies: false,
        nextReplyCursor: ""
      )
    }
  #endif
}
