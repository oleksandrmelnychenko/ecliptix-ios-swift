// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct MessageRecord: Codable, Sendable {
  var messageId: Data
  var conversationId: Data
  var senderMembershipId: Data
  var senderDeviceId: Data
  var senderDisplayName: String?
  var contentType: Int
  var textContent: String?
  var mediaUrl: String?
  var mediaFilename: String?
  var mediaMimeType: String?
  var mediaSizeBytes: Int64?
  var replyToMessageId: Data?
  var forwardedFromMessageId: Data?
  var deliveryStatus: Int
  var sentAt: Int64
  var receivedAt: Int64
  var editedAt: Int64?
  var isDeleted: Bool
  var isSealed: Bool
  var sealedHint: Data?
  var frankingTag: Data?
  var frankingKey: Data?
  var ttlSeconds: Int
  var expiresAt: Int64?
  var senderLeafIndex: Int?
  var generation: Int64?
}

extension MessageRecord: FetchableRecord, MutablePersistableRecord, TableRecord {

  static let databaseTableName = "message"

  static let conversationForeignKey = ForeignKey(["conversationId"])

  static let conversation = belongsTo(ConversationRecord.self, using: conversationForeignKey)
  static let reactions = hasMany(MessageReactionRecord.self)

  var conversation: QueryInterfaceRequest<ConversationRecord> {
    request(for: MessageRecord.conversation)
  }

  var reactions: QueryInterfaceRequest<MessageReactionRecord> {
    request(for: MessageRecord.reactions)
  }
}

extension MessageRecord {

  enum ContentType: Int, Sendable {
    case text = 0
    case image = 1
    case video = 2
    case audio = 3
    case file = 4
    case location = 5
    case contact = 6
    case sticker = 7
  }

  enum DeliveryStatus: Int, Sendable {
    case pending = 0
    case sending = 1
    case sent = 2
    case delivered = 3
    case read = 4
    case failed = 5
  }
}
