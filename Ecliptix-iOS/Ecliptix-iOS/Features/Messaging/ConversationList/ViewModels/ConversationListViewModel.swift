import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftProtobuf
import os.log

@Observable @MainActor
final class ConversationListViewModel: Resettable {

  var conversations: [ConversationDisplayItem] = []
  var pinnedConversations: [ConversationDisplayItem] = []
  var regularConversations: [ConversationDisplayItem] = []
  var searchQuery: String = "" {
    didSet { filterConversations() }
  }

  var isLoading = false
  var hasError = false
  var errorMessage = ""

  private var allConversations: [ConversationDisplayItem] = []
  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private var incomingMessageTask: Task<Void, Never>?
  private var pendingRefreshTask: Task<Void, Never>?

  init(
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadConversations() async {
    isLoading = true
    defer { isLoading = false }

    hasError = false
    errorMessage = ""
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    AppLogger.messaging.info(
      "ConversationList: loading conversations connectId=\(connectId, privacy: .public)"
    )
    let result = await messagingService.listConversations(
      limit: 100,
      cursor: nil,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      allConversations = response.conversations.map { mapConversation($0) }
      sortAndSplit()
      AppLogger.messaging.info(
        "ConversationList: loaded \(self.allConversations.count, privacy: .public) conversations"
      )
    case .err(let rpcError):
      AppLogger.messaging.error(
        "ConversationList: failed to load conversations: \(rpcError.logDescription, privacy: .public)"
      )
      #if DEBUG
        loadMockData()
      #else
        allConversations = []
        conversations = []
        pinnedConversations = []
        regularConversations = []
        hasError = true
        errorMessage = rpcError.userFacingMessage
      #endif
    }
  }

  func refreshConversations() async {
    await loadConversations()
  }

  func startObservingRealtimeUpdates() {
    incomingMessageTask?.cancel()
    incomingMessageTask = Task { [weak self] in
      guard let self else { return }
      let stream = NotificationCenter.default.notifications(named: .messagingIncomingMessage)
      for await notification in stream {
        guard !Task.isCancelled else { break }
        guard
          let conversationId = notification.userInfo?[MessagingNotificationKey.conversationId]
            as? Data,
          let envelope = notification.userInfo?[MessagingNotificationKey.envelope]
            as? ProtoMessageEnvelope
        else {
          continue
        }
        self.handleIncomingMessage(conversationId: conversationId, envelope: envelope)
      }
    }
  }

  func stopObservingRealtimeUpdates() {
    incomingMessageTask?.cancel()
    incomingMessageTask = nil
    pendingRefreshTask?.cancel()
    pendingRefreshTask = nil
  }

  func pinConversation(_ id: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.pinConversation(
      conversationId: id,
      isPinned: true,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "ConversationList: pinConversation failed: \(error.logDescription, privacy: .public)")
      return
    }
    guard let index = allConversations.firstIndex(where: { $0.id == id }) else { return }
    allConversations[index].isPinned = true
    sortAndSplit()
    AppLogger.messaging.info("ConversationList: pinned conversation")
  }

  func unpinConversation(_ id: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.pinConversation(
      conversationId: id,
      isPinned: false,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "ConversationList: unpinConversation failed: \(error.logDescription, privacy: .public)")
      return
    }
    guard let index = allConversations.firstIndex(where: { $0.id == id }) else { return }
    allConversations[index].isPinned = false
    sortAndSplit()
    AppLogger.messaging.info("ConversationList: unpinned conversation")
  }

  func archiveConversation(_ id: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.archiveConversation(
      conversationId: id,
      archive: true,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "ConversationList: archiveConversation failed: \(error.logDescription, privacy: .public)")
      return
    }
    allConversations.removeAll { $0.id == id }
    sortAndSplit()
    AppLogger.messaging.info("ConversationList: archived conversation")
  }

  func muteConversation(_ id: Data, status: ProtoMuteStatus) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.muteConversation(
      conversationId: id,
      muteStatus: status,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "ConversationList: muteConversation failed: \(error.logDescription, privacy: .public)")
      return
    }
    guard let index = allConversations.firstIndex(where: { $0.id == id }) else { return }
    allConversations[index].isMuted = status != .unmuted
    sortAndSplit()
    AppLogger.messaging.info("ConversationList: mute status changed")
  }

  func deleteConversation(_ id: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.deleteConversation(
      conversationId: id,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "ConversationList: deleteConversation failed: \(error.logDescription, privacy: .public)")
      return
    }
    allConversations.removeAll { $0.id == id }
    sortAndSplit()
    AppLogger.messaging.info("ConversationList: deleted conversation")
  }

  func resetState() {
    stopObservingRealtimeUpdates()
    allConversations = []
    conversations = []
    pinnedConversations = []
    regularConversations = []
    searchQuery = ""
    isLoading = false
    hasError = false
    errorMessage = ""
  }

  private func filterConversations() {
    guard !searchQuery.isEmpty else {
      sortAndSplit()
      return
    }

    let query = searchQuery.lowercased()
    let filtered = allConversations.filter { item in
      item.title.lowercased().contains(query)
        || item.lastMessagePreview.lowercased().contains(query)
        || item.lastMessageSenderName.lowercased().contains(query)
    }
    conversations = filtered
    pinnedConversations = filtered.filter(\.isPinned)
    regularConversations = filtered.filter { !$0.isPinned }
  }

  private func sortAndSplit() {
    let sorted = allConversations.sorted { lhs, rhs in
      (lhs.lastMessageDate ?? .distantPast) > (rhs.lastMessageDate ?? .distantPast)
    }
    if searchQuery.isEmpty {
      conversations = sorted
      pinnedConversations = sorted.filter(\.isPinned)
      regularConversations = sorted.filter { !$0.isPinned }
    } else {
      filterConversations()
    }
  }

  private func handleIncomingMessage(conversationId: Data, envelope: ProtoMessageEnvelope) {
    guard let index = allConversations.firstIndex(where: { $0.id == conversationId }) else {
      scheduleRefresh()
      return
    }

    let existing = allConversations[index]
    let isOwnMessage = currentMembershipId.map { envelope.senderID == $0 } ?? false
    let updated = ConversationDisplayItem(
      id: existing.id,
      type: existing.type,
      title: existing.title,
      avatarUrl: existing.avatarUrl,
      lastMessagePreview: previewText(for: envelope),
      lastMessageSenderName: existing.lastMessageSenderName,
      lastMessageContentType: messageContentType(for: envelope),
      lastMessageDate: envelope.createdAt.date,
      unreadCount: isOwnMessage ? existing.unreadCount : existing.unreadCount + 1,
      isPinned: existing.isPinned,
      isMuted: existing.isMuted,
      memberCount: existing.memberCount
    )
    allConversations[index] = updated
    sortAndSplit()
  }

  private func scheduleRefresh() {
    pendingRefreshTask?.cancel()
    pendingRefreshTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(400))
      guard !Task.isCancelled else { return }
      await self?.loadConversations()
    }
  }

  private func mapConversation(_ proto: ProtoConversationInfo) -> ConversationDisplayItem {
    let conversationType: ConversationDisplayItem.ConversationType
    switch proto.conversationType {
    case .direct: conversationType = .direct
    case .group: conversationType = .group
    case .channel: conversationType = .channel
    default: conversationType = .unspecified
    }

    let lastMessageDate =
      proto.lastMessageAt.seconds > 0
      ? Date(timeIntervalSince1970: TimeInterval(proto.lastMessageAt.seconds))
      : nil
    let title: String
    if proto.hasTitle, !proto.title.isEmpty {
      title = proto.title
    } else if conversationType == .group {
      title = String(localized: "Group")
    } else if conversationType == .channel {
      title = String(localized: "Channel")
    } else {
      title = String(localized: "Direct chat")
    }
    return ConversationDisplayItem(
      id: proto.conversationID,
      type: conversationType,
      title: title,
      avatarUrl: nil,
      lastMessagePreview: "",
      lastMessageSenderName: "",
      lastMessageContentType: .unspecified,
      lastMessageDate: lastMessageDate,
      unreadCount: Int32(proto.unreadCount),
      isPinned: proto.isPinned,
      isMuted: proto.isMuted,
      memberCount: proto.participants.count
    )
  }

  private func previewText(for envelope: ProtoMessageEnvelope) -> String {
    switch envelope.content.content {
    case .text(let text):
      return text.body
    case .media:
      return String(localized: "Media")
    case .location:
      return String(localized: "Location")
    case .contact:
      return String(localized: "Contact")
    case .none:
      return ""
    }
  }

  private func messageContentType(for envelope: ProtoMessageEnvelope)
    -> ConversationDisplayItem.MessageContentType
  {
    switch envelope.content.content {
    case .text:
      return .text
    case .media:
      return .image
    case .location:
      return .location
    case .contact:
      return .contact
    case .none:
      return .unspecified
    }
  }

  private var currentMembershipId: Data? {
    settingsProvider()?.membership?.membershipId.protobufBytes
  }

  private func loadMockData() {
    let now = Date()
    let calendar = Calendar.current

    allConversations = [
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "Sarah Chen", avatarUrl: nil,
        lastMessagePreview: "Hey, are we still meeting tomorrow at 3?",
        lastMessageSenderName: "", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .minute, value: -5, to: now),
        unreadCount: 2, isPinned: true, isMuted: false, memberCount: 2
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .group,
        title: "Design Team", avatarUrl: nil,
        lastMessagePreview: "I've uploaded the new mockups to Figma",
        lastMessageSenderName: "Alex Rivera", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .minute, value: -22, to: now),
        unreadCount: 5, isPinned: true, isMuted: false, memberCount: 8
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "Marcus Johnson", avatarUrl: nil,
        lastMessagePreview: "Thanks for sending that over!",
        lastMessageSenderName: "", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .hour, value: -1, to: now),
        unreadCount: 0, isPinned: false, isMuted: false, memberCount: 2
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .group,
        title: "Project Alpha", avatarUrl: nil,
        lastMessagePreview: "Sprint planning starts at 10am",
        lastMessageSenderName: "Priya Patel", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .hour, value: -3, to: now),
        unreadCount: 12, isPinned: false, isMuted: false, memberCount: 15
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "Emma Wilson", avatarUrl: nil,
        lastMessagePreview: "Sent a photo",
        lastMessageSenderName: "", lastMessageContentType: .image,
        lastMessageDate: calendar.date(byAdding: .day, value: -1, to: now),
        unreadCount: 0, isPinned: false, isMuted: false, memberCount: 2
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .group,
        title: "Weekend Hiking", avatarUrl: nil,
        lastMessagePreview: "The trail conditions look great for Saturday",
        lastMessageSenderName: "Jordan Lee", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .day, value: -1, to: now),
        unreadCount: 3, isPinned: false, isMuted: true, memberCount: 6
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "David Kim", avatarUrl: nil,
        lastMessagePreview: "Can you review the PR when you get a chance?",
        lastMessageSenderName: "", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .day, value: -2, to: now),
        unreadCount: 1, isPinned: false, isMuted: false, memberCount: 2
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "Olivia Martinez", avatarUrl: nil,
        lastMessagePreview: "Voice message",
        lastMessageSenderName: "", lastMessageContentType: .audio,
        lastMessageDate: calendar.date(byAdding: .day, value: -3, to: now),
        unreadCount: 0, isPinned: false, isMuted: false, memberCount: 2
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .group,
        title: "Family Chat", avatarUrl: nil,
        lastMessagePreview: "Happy birthday! 🎂",
        lastMessageSenderName: "Mom", lastMessageContentType: .text,
        lastMessageDate: calendar.date(byAdding: .day, value: -5, to: now),
        unreadCount: 0, isPinned: false, isMuted: false, memberCount: 12
      ),
      ConversationDisplayItem(
        id: UUID().protobufBytes, type: .direct,
        title: "Nathan Brooks", avatarUrl: nil,
        lastMessagePreview: "Shared a location",
        lastMessageSenderName: "", lastMessageContentType: .location,
        lastMessageDate: calendar.date(byAdding: .day, value: -7, to: now),
        unreadCount: 0, isPinned: false, isMuted: true, memberCount: 2
      ),
    ]

    sortAndSplit()
    AppLogger.messaging.info(
      "ConversationList: loaded \(self.allConversations.count, privacy: .public) mock conversations"
    )
  }
}
