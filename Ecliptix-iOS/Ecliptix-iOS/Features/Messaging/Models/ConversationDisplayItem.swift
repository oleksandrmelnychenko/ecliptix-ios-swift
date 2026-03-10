// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct ConversationDisplayItem: Identifiable, Hashable, Sendable {

  let id: Data
  let type: ConversationType
  let title: String
  let avatarUrl: String?
  let lastMessagePreview: String
  let lastMessageSenderName: String
  let lastMessageContentType: MessageContentType
  let lastMessageDate: Date?
  let unreadCount: Int32
  var isPinned: Bool
  var isMuted: Bool
  let memberCount: Int

  var isGroup: Bool { type == .group }
  var isChannel: Bool { type == .channel }

  enum ConversationType: Int, Sendable {
    case unspecified = 0
    case direct = 1
    case group = 2
    case channel = 3
  }

  enum MessageContentType: Int, Sendable {
    case unspecified = 0
    case text = 1
    case image = 2
    case video = 3
    case audio = 4
    case file = 5
    case location = 6
    case contact = 7
    case system = 8
  }
}
