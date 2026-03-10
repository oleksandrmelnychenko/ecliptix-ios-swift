// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct MessageReactionRecord: Codable, Sendable {
  var messageId: Data
  var membershipId: Data
  var emoji: String
  var reactedAt: Int64
}

extension MessageReactionRecord: FetchableRecord, PersistableRecord, TableRecord {
  static let databaseTableName = "messageReaction"

  static let message = belongsTo(MessageRecord.self)

  var message: QueryInterfaceRequest<MessageRecord> {
    request(for: MessageReactionRecord.message)
  }
}
