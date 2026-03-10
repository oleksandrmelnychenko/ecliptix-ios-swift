// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

@Observable @MainActor
final class ChannelFeedViewModel: Resettable {

  var posts: [ChannelPostDisplayItem] = []
  var channelTitle: String = ""
  var channelDescription: String = ""
  var subscriberCount: Int32 = 0
  var isAdmin: Bool = false
  var isLoading: Bool = false
  var isSending: Bool = false
  var hasMorePosts: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var inputText: String = ""

  let channelId: Data
  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private var viewTrackingTask: Task<Void, Never>?
  private var recordedPostViewIDs: Set<Data> = []

  init(
    channelId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.channelId = channelId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadChannel() async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.getConversation(
      conversationId: channelId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let conv = response.conversation
      channelTitle = conv.title
      channelDescription = conv.description_p
      subscriberCount = conv.subscriberCount
      resolveAdminStatus(from: conv)
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelFeed: loadChannel failed: \(error.logDescription, privacy: .public)")
    }
  }

  func loadPosts() async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.listMessages(
      conversationId: channelId,
      pageSize: 30,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let currentMembershipId = settingsProvider()?.membership?.membershipId.protobufBytes
      posts = response.messages.map {
        ChannelPostDisplayItem(from: $0, currentMembershipId: currentMembershipId)
      }
      hasMorePosts = response.hasMore_p
      hasError = false
      recordViewsForVisiblePosts()
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelFeed: loadPosts failed: \(error.logDescription, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
    }
  }

  func loadMorePosts() async {
    guard hasMorePosts, !isLoading, let lastPost = posts.last else { return }
    isLoading = true
    defer { isLoading = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.listMessages(
      conversationId: channelId,
      pageSize: 30,
      beforeMessageId: lastPost.id,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let currentMembershipId = settingsProvider()?.membership?.membershipId.protobufBytes
      let newPosts = response.messages.map {
        ChannelPostDisplayItem(from: $0, currentMembershipId: currentMembershipId)
      }
      posts.append(contentsOf: newPosts)
      hasMorePosts = response.hasMore_p
      recordViewsForVisiblePosts()
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelFeed: loadMore failed: \(error.logDescription, privacy: .public)")
    }
  }

  func sendPost() async {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, isAdmin else { return }
    isSending = true
    defer { isSending = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.sendMessage(
      conversationId: channelId,
      textContent: text,
      replyToMessageId: nil,
      clientMessageId: UUID().uuidString,
      connectId: connectId
    )
    switch result {
    case .ok:
      inputText = ""
      await loadPosts()
    case .err(let rpcError):
      AppLogger.messaging.error(
        "ChannelFeed: failed to send post: \(rpcError.logDescription, privacy: .public)")
      hasError = true
      errorMessage = rpcError.userFacingMessage
    }
  }

  func deletePost(_ postId: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.deleteMessage(
      messageId: postId,
      conversationId: channelId,
      deleteForEveryone: true,
      connectId: connectId
    )
    switch result {
    case .ok:
      posts.removeAll { $0.id == postId }
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelFeed: deletePost failed: \(error.logDescription, privacy: .public)")
    }
  }

  func resetState() {
    viewTrackingTask?.cancel()
    viewTrackingTask = nil
    posts = []
    recordedPostViewIDs = []
    channelTitle = ""
    channelDescription = ""
    subscriberCount = 0
    isAdmin = false
    isLoading = false
    isSending = false
    hasMorePosts = false
    hasError = false
    errorMessage = ""
    inputText = ""
  }

  private func recordViewsForVisiblePosts() {
    let ids = posts.map(\.id).filter { !recordedPostViewIDs.contains($0) }
    guard !ids.isEmpty else { return }
    viewTrackingTask?.cancel()
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    viewTrackingTask = Task { [weak self] in
      guard let self else { return }
      let result = await self.messagingService.recordPostView(
        channelId: self.channelId,
        messageIds: ids,
        connectId: connectId
      )
      guard result.isOk else { return }
      self.recordedPostViewIDs.formUnion(ids)
    }
  }

  private func resolveAdminStatus(from conv: ProtoConversation) {
    guard let membershipId = settingsProvider()?.membership?.membershipId else { return }
    let membershipBytes = membershipId.protobufBytes
    for member in conv.members {
      if member.membershipID == membershipBytes {
        isAdmin = member.role == .owner || member.role == .admin
        return
      }
    }
  }
}
