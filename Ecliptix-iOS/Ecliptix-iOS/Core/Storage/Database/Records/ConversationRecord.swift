// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct ConversationRecord: Codable, Sendable {
  var conversationId: Data
  var groupId: Data
  var type: Int
  var status: Int
  var title: String?
  var avatarUrl: String?
  var conversationDescription: String?
  var createdAt: Int64
  var updatedAt: Int64
  var lastMessageAt: Int64?
  var lastMessagePreview: String?
  var unreadCount: Int
  var isPinned: Bool
  var muteStatus: Int
  var isArchived: Bool
}

extension ConversationRecord: FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "conversation"
}

extension ConversationRecord {

  static let members = hasMany(
    ConversationMemberRecord.self, using: ConversationMemberRecord.conversationForeignKey)
  static let messages = hasMany(MessageRecord.self, using: MessageRecord.conversationForeignKey)
  static let cryptoSession = hasOne(CryptoSessionRecord.self)

  var members: QueryInterfaceRequest<ConversationMemberRecord> {
    request(for: ConversationRecord.members)
  }

  var messages: QueryInterfaceRequest<MessageRecord> {
    request(for: ConversationRecord.messages)
  }
}
