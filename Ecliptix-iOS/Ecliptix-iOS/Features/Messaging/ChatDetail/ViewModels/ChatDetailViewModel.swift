import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftProtobuf
import os

struct ChatMessageGroup: Hashable {
  let date: Date
  let messages: [MessageDisplayItem]

  func hash(into hasher: inout Hasher) {
    hasher.combine(date)
  }

  static func == (lhs: ChatMessageGroup, rhs: ChatMessageGroup) -> Bool {
    lhs.date == rhs.date
  }
}

@Observable @MainActor
final class ChatDetailViewModel: Resettable {

  var messages: [MessageDisplayItem] = [] {
    didSet { rebuildGroupedMessages() }
  }
  private(set) var cachedGroupedMessages: [ChatMessageGroup] = []
  var inputText: String = ""
  var conversationTitle: String = ""
  var conversationAvatarUrl: String?
  var isGroup: Bool = false
  var isOnline: Bool = false
  var isLoading: Bool = false
  var isSending: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var typingUserName: String = ""
  var isTyping: Bool = false
  var replyingToMessage: MessageDisplayItem?
  var hasMoreMessages: Bool = true
  var showScrollToBottom: Bool = false

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let conversationId: Data
  private var oldestMessageId: Data?
  private var knownMessageIds: Set<Data> = []
  private var incomingMessageTask: Task<Void, Never>?
  private var typingIndicatorTask: Task<Void, Never>?
  private var typingResetTask: Task<Void, Never>?

  init(
    conversationId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.conversationId = conversationId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func startObservingIncomingMessages() {
    incomingMessageTask?.cancel()
    typingIndicatorTask?.cancel()
    incomingMessageTask = Task { [weak self] in
      guard let self else { return }
      let stream = NotificationCenter.default.notifications(
        named: .messagingIncomingMessage
      )
      for await notification in stream {
        guard !Task.isCancelled else { break }
        guard
          let convId = notification.userInfo?[MessagingNotificationKey.conversationId] as? Data,
          let envelope = notification.userInfo?[MessagingNotificationKey.envelope]
            as? ProtoMessageEnvelope,
          convId == self.conversationId
        else { continue }
        self.appendIncomingEnvelope(envelope)
      }
    }
    typingIndicatorTask = Task { [weak self] in
      guard let self else { return }
      let stream = NotificationCenter.default.notifications(
        named: .messagingTypingEvent
      )
      for await notification in stream {
        guard !Task.isCancelled else { break }
        self.handleTypingNotification(notification)
      }
    }
  }

  func stopObservingIncomingMessages() {
    incomingMessageTask?.cancel()
    incomingMessageTask = nil
    typingIndicatorTask?.cancel()
    typingIndicatorTask = nil
    typingResetTask?.cancel()
    typingResetTask = nil
    clearTypingIndicator()
  }

  private func appendIncomingEnvelope(_ envelope: ProtoMessageEnvelope) {
    if let index = messages.firstIndex(where: { $0.id == envelope.messageID }) {
      messages[index] = mapIncomingEnvelope(envelope, preserving: messages[index])
      return
    }
    let item = mapIncomingEnvelope(envelope)
    knownMessageIds.insert(item.id)
    messages.append(item)
    AppLogger.messaging.debug(
      "ChatDetail: appended incoming message \(envelope.messageID.hexString, privacy: .public)"
    )
    if !item.isOwnMessage {
      Task { await markAsRead() }
    }
  }

  private func mapIncomingEnvelope(
    _ envelope: ProtoMessageEnvelope,
    preserving existing: MessageDisplayItem? = nil
  ) -> MessageDisplayItem {
    let isOwnMessage = currentMembershipId.map { envelope.senderID == $0 } ?? false
    let contentType: MessageDisplayItem.ContentType
    let textContent: String
    switch envelope.content.content {
    case .text(let t):
      contentType = .text
      textContent = t.body
    case .media:
      contentType = .image
      textContent = ""
    case .location:
      contentType = .location
      textContent = ""
    case .contact:
      contentType = .contact
      textContent = ""
    case .none:
      contentType = .unspecified
      textContent = ""
    }

    return MessageDisplayItem(
      id: envelope.messageID,
      conversationId: envelope.conversationID,
      senderMembershipId: envelope.senderID,
      senderAccountId: envelope.senderAccountID,
      senderDisplayName: existing?.senderDisplayName ?? "",
      isOwnMessage: isOwnMessage,
      contentType: contentType,
      textContent: textContent,
      mediaUrl: existing?.mediaUrl,
      mediaThumbnailUrl: existing?.mediaThumbnailUrl,
      mediaFilename: existing?.mediaFilename,
      replyToPreview: existing?.replyToPreview,
      replyToSenderName: existing?.replyToSenderName,
      deliveryStatus: .delivered,
      sentAt: envelope.createdAt.date,
      isEdited: envelope.hasEditedAt,
      isDeleted: envelope.isTombstoned,
      reactions: existing?.reactions ?? [],
      readCount: existing?.readCount ?? 0
    )
  }

  private func handleTypingNotification(_ notification: Notification) {
    guard
      let convId = notification.userInfo?[MessagingNotificationKey.conversationId] as? Data,
      convId == conversationId,
      let membershipId = notification.userInfo?[MessagingNotificationKey.membershipId] as? Data,
      membershipId != currentMembershipId,
      let isTyping = notification.userInfo?[MessagingNotificationKey.isTyping] as? Bool
    else {
      return
    }

    if isTyping {
      let displayName =
        (notification.userInfo?[MessagingNotificationKey.displayName] as? String)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
      typingUserName =
        (displayName?.isEmpty == false)
        ? (displayName ?? String(localized: "Someone"))
        : String(localized: "Someone")
      self.isTyping = true
      typingResetTask?.cancel()
      typingResetTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        self?.clearTypingIndicator()
      }
    } else {
      typingResetTask?.cancel()
      typingResetTask = nil
      clearTypingIndicator()
    }
  }

  private func clearTypingIndicator() {
    typingUserName = ""
    isTyping = false
  }

  func loadInitialMessages() async {
    isLoading = true
    defer { isLoading = false }

    hasError = false
    errorMessage = ""

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    await loadConversationInfo(connectId: connectId)

    let result = await messagingService.listMessages(
      conversationId: conversationId,
      pageSize: 50,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      messages = response.messages.map { mapMessage($0) }
      knownMessageIds = Set(messages.map(\.id))
      hasMoreMessages = response.hasMore_p
      oldestMessageId = response.messages.first?.messageID
    case .err(let rpcError):
      AppLogger.messaging.error(
        "ChatDetail: failed to load messages: \(rpcError.logDescription, privacy: .public)")
      #if DEBUG
        loadMockMessages()
      #else
        messages = []
        hasMoreMessages = false
        oldestMessageId = nil
        hasError = true
        errorMessage = rpcError.userFacingMessage
      #endif
    }
  }

  func loadMoreMessages() async {
    guard hasMoreMessages, !isLoading else { return }
    isLoading = true
    defer { isLoading = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await messagingService.listMessages(
      conversationId: conversationId,
      pageSize: 30,
      beforeMessageId: oldestMessageId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let newMessages = response.messages.map { mapMessage($0) }
        .filter { !knownMessageIds.contains($0.id) }
      knownMessageIds.formUnion(newMessages.map(\.id))
      messages.insert(contentsOf: newMessages, at: 0)
      hasMoreMessages = response.hasMore_p
      if let first = response.messages.first {
        oldestMessageId = first.messageID
      }
    case .err(let error):
      AppLogger.messaging.error("Failed to load more messages: \(error, privacy: .public)")
    }
  }

  func sendMessage() async {
    let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    guard let identity = currentIdentity else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("ChatDetail: missing identity for sendMessage")
      return
    }
    isSending = true
    defer { isSending = false }

    inputText = ""

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)

    let result = await messagingService.sendMessage(
      conversationId: conversationId,
      textContent: text,
      replyToMessageId: replyingToMessage?.id,
      clientMessageId: UUID().uuidString,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let confirmed = MessageDisplayItem(
        id: response.messageID,
        conversationId: conversationId,
        senderMembershipId: identity.membershipId,
        senderAccountId: identity.accountId,
        senderDisplayName: "You",
        isOwnMessage: true,
        contentType: .text,
        textContent: text,
        mediaUrl: nil, mediaThumbnailUrl: nil, mediaFilename: nil,
        replyToPreview: replyingToMessage?.textContent,
        replyToSenderName: replyingToMessage?.senderDisplayName,
        deliveryStatus: .sent,
        sentAt: response.serverTimestamp.date,
        isEdited: false,
        isDeleted: false,
        reactions: [],
        readCount: 0
      )
      knownMessageIds.insert(confirmed.id)
      messages.append(confirmed)
    case .err(let error):
      AppLogger.messaging.error("Failed to send: \(error, privacy: .public)")
      errorMessage = String(localized: "Failed to send message")
      hasError = true
      inputText = text
    }
    replyingToMessage = nil
  }

  func deleteMessage(_ id: Data, forEveryone: Bool) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let deleteResult = await messagingService.deleteMessage(
      messageId: id,
      conversationId: conversationId,
      deleteForEveryone: forEveryone,
      connectId: connectId
    )
    if let error = deleteResult.err() {
      AppLogger.messaging.warning("Failed to delete message: \(error, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
      return
    }
    messages.removeAll { $0.id == id }
  }

  func reactToMessage(_ id: Data, emoji: String) async {
    let shouldRemove =
      messages.first(where: { $0.id == id })?.reactions.first(where: { $0.emoji == emoji })?
      .reactedByMe ?? false
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let reactResult = await messagingService.reactToMessage(
      messageId: id,
      conversationId: conversationId,
      emoji: emoji,
      remove: shouldRemove,
      connectId: connectId
    )
    if let error = reactResult.err() {
      AppLogger.messaging.warning(
        "Failed to react to message: \(error.logDescription, privacy: .public)")
      return
    }
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    var existing = messages[index].reactions
    if let reactionIndex = existing.firstIndex(where: { $0.emoji == emoji }) {
      let reaction = existing[reactionIndex]
      let reactedByMe = reaction.reactedByMe
      if reactedByMe {
        // toggle off
        let newCount = reaction.count - 1
        if newCount <= 0 {
          existing.remove(at: reactionIndex)
        } else {
          existing[reactionIndex] = MessageDisplayItem.ReactionDisplay(
            emoji: emoji, count: newCount, reactedByMe: false
          )
        }
      } else {
        existing[reactionIndex] = MessageDisplayItem.ReactionDisplay(
          emoji: emoji, count: reaction.count + 1, reactedByMe: true
        )
      }
    } else {
      existing.append(MessageDisplayItem.ReactionDisplay(emoji: emoji, count: 1, reactedByMe: true))
    }
    messages[index].reactions = existing
  }

  func sendTypingIndicator(isTyping: Bool) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.sendTypingIndicator(
      conversationId: conversationId,
      isTyping: isTyping,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.debug(
        "sendTypingIndicator failed: \(error.logDescription, privacy: .public)")
    }
  }

  func editMessage(_ id: Data, newText: String) async {
    let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.editMessage(
      messageId: id,
      conversationId: conversationId,
      textContent: trimmed,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning("editMessage failed: \(error.logDescription, privacy: .public)")
      return
    }
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].textContent = trimmed
    messages[index].isEdited = true
  }

  func forwardMessage(_ messageId: Data, toConversationId: Data) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.forwardMessage(
      messageId: messageId,
      targetConversationId: toConversationId,
      connectId: connectId
    )
    if let error = result.err() {
      AppLogger.messaging.warning(
        "forwardMessage failed: \(error.logDescription, privacy: .public)")
    }
  }

  func markAsRead() async {
    guard let lastMessage = messages.last else { return }
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let markReadResult = await messagingService.markRead(
      conversationId: conversationId,
      upToMessageId: lastMessage.id,
      connectId: connectId
    )
    if let error = markReadResult.err() {
      AppLogger.messaging.warning("Failed to mark read: \(error, privacy: .public)")
    }
  }

  func setReplyTarget(_ message: MessageDisplayItem?) {
    replyingToMessage = message
  }

  func resetState() {
    stopObservingIncomingMessages()
    messages = []
    knownMessageIds = []
    inputText = ""
    isLoading = false
    isSending = false
    hasError = false
    errorMessage = ""
    replyingToMessage = nil
    oldestMessageId = nil
    hasMoreMessages = true
    showScrollToBottom = false
    typingUserName = ""
    isTyping = false
  }

  private func loadConversationInfo(connectId: UInt32) async {
    let result = await messagingService.getConversation(
      conversationId: conversationId,
      connectId: connectId
    )
    if case .ok(let response) = result {
      let conv = response.conversation
      conversationTitle = conv.title
      isGroup = conv.type == .group
      if conv.hasAvatarURL {
        conversationAvatarUrl = conv.avatarURL
      }
    } else if case .err(let rpcError) = result {
      AppLogger.messaging.warning(
        "ChatDetail: failed to load conversation info: \(rpcError.logDescription, privacy: .public)"
      )
    }
  }

  private var currentMembershipId: Data? {
    settingsProvider()?.membership?.membershipId.protobufBytes
  }

  private var currentAccountId: Data? {
    settingsProvider()?.currentAccountId?.protobufBytes
  }

  private var currentIdentity: (membershipId: Data, accountId: Data)? {
    guard let currentMembershipId,
      let currentAccountId
    else {
      return nil
    }
    return (membershipId: currentMembershipId, accountId: currentAccountId)
  }

  private func mapMessage(_ proto: ProtoChatMessage) -> MessageDisplayItem {
    let isOwnMessage = currentMembershipId.map { proto.senderMembershipID == $0 } ?? false
    return MessageDisplayItem(
      id: proto.messageID,
      conversationId: proto.conversationID,
      senderMembershipId: proto.senderMembershipID,
      senderAccountId: proto.senderAccountID,
      senderDisplayName: proto.senderDisplayName,
      isOwnMessage: isOwnMessage,
      contentType: MessageDisplayItem.ContentType(rawValue: proto.contentType.rawValue) ?? .text,
      textContent: proto.textContent,
      mediaUrl: proto.hasMedia ? proto.media.url : nil,
      mediaThumbnailUrl: proto.hasMedia ? proto.media.thumbnailURL : nil,
      mediaFilename: proto.hasMedia ? proto.media.filename : nil,
      replyToPreview: nil,
      replyToSenderName: nil,
      deliveryStatus: MessageDisplayItem.DeliveryStatus(rawValue: proto.deliveryStatus.rawValue)
        ?? .sent,
      sentAt: proto.sentAt.date,
      isEdited: proto.hasEditedAt,
      isDeleted: proto.isDeleted,
      reactions: aggregateReactions(proto.reactions),
      readCount: proto.readReceipts.count
    )
  }

  private func aggregateReactions(_ reactions: [ProtoMessageReaction]) -> [MessageDisplayItem
    .ReactionDisplay]
  {
    var grouped: [String: (count: Int, reactedByMe: Bool)] = [:]
    for reaction in reactions {
      let existing = grouped[reaction.emoji, default: (count: 0, reactedByMe: false)]
      let reactedByMe = currentMembershipId.map { reaction.membershipID == $0 } ?? false
      grouped[reaction.emoji] = (
        count: existing.count + 1,
        reactedByMe: existing.reactedByMe || reactedByMe
      )
    }
    return grouped.map { emoji, value in
      MessageDisplayItem.ReactionDisplay(
        emoji: emoji, count: value.count, reactedByMe: value.reactedByMe)
    }
  }

  private func rebuildGroupedMessages() {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: messages) { message in
      calendar.startOfDay(for: message.sentAt)
    }
    cachedGroupedMessages =
      grouped
      .sorted { $0.key < $1.key }
      .map { ChatMessageGroup(date: $0.key, messages: $0.value) }
  }

  private func loadMockMessages() {
    conversationTitle = "Alice Johnson"
    isOnline = true

    let now = Date()
    messages = [
      MessageDisplayItem(
        id: Data([1]), conversationId: conversationId,
        senderMembershipId: Data([2]), senderAccountId: Data(repeating: 2, count: 16),
        senderDisplayName: "Alice Johnson",
        isOwnMessage: false, contentType: .text,
        textContent: "Hey! How are you doing?",
        mediaUrl: nil, mediaThumbnailUrl: nil, mediaFilename: nil,
        replyToPreview: nil, replyToSenderName: nil,
        deliveryStatus: .read, sentAt: now.addingTimeInterval(-3600),
        isEdited: false, isDeleted: false, reactions: [], readCount: 1
      ),
      MessageDisplayItem(
        id: Data([2]), conversationId: conversationId,
        senderMembershipId: Data([1]), senderAccountId: Data(repeating: 1, count: 16),
        senderDisplayName: "You",
        isOwnMessage: true, contentType: .text,
        textContent: "I'm great, thanks! Just working on the new messaging feature.",
        mediaUrl: nil, mediaThumbnailUrl: nil, mediaFilename: nil,
        replyToPreview: nil, replyToSenderName: nil,
        deliveryStatus: .delivered, sentAt: now.addingTimeInterval(-3500),
        isEdited: false, isDeleted: false, reactions: [], readCount: 0
      ),
      MessageDisplayItem(
        id: Data([3]), conversationId: conversationId,
        senderMembershipId: Data([2]), senderAccountId: Data(repeating: 2, count: 16),
        senderDisplayName: "Alice Johnson",
        isOwnMessage: false, contentType: .text,
        textContent: "That's awesome! Can't wait to try it out",
        mediaUrl: nil, mediaThumbnailUrl: nil, mediaFilename: nil,
        replyToPreview: nil, replyToSenderName: nil,
        deliveryStatus: .read, sentAt: now.addingTimeInterval(-3400),
        isEdited: false, isDeleted: false, reactions: [], readCount: 1
      ),
      MessageDisplayItem(
        id: Data([4]), conversationId: conversationId,
        senderMembershipId: Data([1]), senderAccountId: Data(repeating: 1, count: 16),
        senderDisplayName: "You",
        isOwnMessage: true, contentType: .text,
        textContent: "It should be ready soon! The E2EE is already working",
        mediaUrl: nil, mediaThumbnailUrl: nil, mediaFilename: nil,
        replyToPreview: nil, replyToSenderName: nil,
        deliveryStatus: .sent, sentAt: now.addingTimeInterval(-60),
        isEdited: false, isDeleted: false, reactions: [], readCount: 0
      ),
    ]
  }
}
