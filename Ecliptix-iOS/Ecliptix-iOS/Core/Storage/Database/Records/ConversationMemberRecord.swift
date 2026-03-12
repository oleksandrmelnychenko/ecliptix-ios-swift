// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct ConversationMemberRecord: Codable, Sendable {

  var conversationId: Data
  var membershipId: Data
  var accountId: Data
  var deviceId: Data
  var leafIndex: Int
  var role: Int
  var displayName: String
  var handle: String?
  var avatarUrl: String?
  var joinedAt: Int64
}

extension ConversationMemberRecord: FetchableRecord, PersistableRecord, TableRecord {

  static let databaseTableName = "conversationMember"

  static let conversationForeignKey = ForeignKey(["conversationId"])

  static let conversation = belongsTo(ConversationRecord.self, using: conversationForeignKey)

  var conversation: QueryInterfaceRequest<ConversationRecord> {
    request(for: ConversationMemberRecord.conversation)
  }
}

extension ConversationMemberRecord {

  enum MemberRole: Int, Sendable {
    case member = 0
    case admin = 1
    case owner = 2
  }
}
