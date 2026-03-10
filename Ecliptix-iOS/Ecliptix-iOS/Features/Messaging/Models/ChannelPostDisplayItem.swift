// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf

struct ChannelPostDisplayItem: Identifiable, Hashable, Sendable {

  let id: Data
  let channelId: Data
  let authorId: Data
  let authorAccountId: Data
  let authorName: String
  let authorSignature: String?
  let contentType: MessageDisplayItem.ContentType
  var textContent: String
  let mediaUrl: String?
  let mediaThumbnailUrl: String?
  var viewCount: Int32
  var forwardCount: Int32
  let isSilent: Bool
  var isPinned: Bool
  let isDeleted: Bool
  let sentAt: Date
  var isEdited: Bool
  var reactions: [MessageDisplayItem.ReactionDisplay]

  init(from proto: ProtoChatMessage, isPinned: Bool = false, currentMembershipId: Data? = nil) {
    self.id = proto.messageID
    self.channelId = proto.conversationID
    self.authorId = proto.senderMembershipID
    self.authorAccountId = proto.senderAccountID
    self.authorName = proto.senderDisplayName
    self.authorSignature = proto.hasAuthorSignature ? proto.authorSignature : nil
    self.contentType = MessageDisplayItem.ContentType(rawValue: proto.contentType.rawValue) ?? .unspecified
    self.textContent = proto.textContent
    self.mediaUrl = proto.hasMedia ? proto.media.url : nil
    self.mediaThumbnailUrl = proto.hasMedia ? proto.media.thumbnailURL : nil
    self.viewCount = proto.viewCount
    self.forwardCount = proto.forwardCount
    self.isSilent = proto.isSilent
    self.isPinned = isPinned
    self.isDeleted = proto.isDeleted
    self.sentAt = proto.hasSentAt ? proto.sentAt.date : Date()
    self.isEdited = proto.hasEditedAt

    var reactionMap: [String: (count: Int, reactedByMe: Bool)] = [:]
    for reaction in proto.reactions {
      let emoji = reaction.emoji
      var entry = reactionMap[emoji] ?? (0, false)
      entry.count += 1
      if let currentMembershipId {
        entry.reactedByMe = entry.reactedByMe || reaction.membershipID == currentMembershipId
      }
      reactionMap[emoji] = entry
    }
    self.reactions = reactionMap.map { emoji, info in
      MessageDisplayItem.ReactionDisplay(emoji: emoji, count: info.count, reactedByMe: info.reactedByMe)
    }
  }
}
