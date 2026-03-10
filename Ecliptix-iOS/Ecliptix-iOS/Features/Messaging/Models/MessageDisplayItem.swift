// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct MessageDisplayItem: Identifiable, Hashable, Sendable {

  let id: Data
  let conversationId: Data
  let senderMembershipId: Data
  let senderAccountId: Data
  let senderDisplayName: String
  let isOwnMessage: Bool
  let contentType: ContentType
  var textContent: String
  let mediaUrl: String?
  let mediaThumbnailUrl: String?
  let mediaFilename: String?
  let replyToPreview: String?
  let replyToSenderName: String?
  let deliveryStatus: DeliveryStatus
  let sentAt: Date
  var isEdited: Bool
  let isDeleted: Bool
  var reactions: [ReactionDisplay]
  let readCount: Int

  enum ContentType: Int, Sendable {
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

  enum DeliveryStatus: Int, Sendable {
    case unspecified = 0
    case sending = 1
    case sent = 2
    case delivered = 3
    case read = 4
    case failed = 5
  }

  struct ReactionDisplay: Hashable, Sendable {

    let emoji: String
    let count: Int
    let reactedByMe: Bool
  }
}
