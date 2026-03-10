// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct OutboxRecord: Codable, Sendable {
  var id: Int64?
  var conversationId: Data
  var payloadType: Int
  var payload: Data
  var createdAt: Int64
  var retryCount: Int
  var lastAttemptAt: Int64?
}

extension OutboxRecord: FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "outbox"

  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

extension OutboxRecord {
  enum PayloadType: Int, Sendable {
    case groupMessage = 1
    case groupCommit = 2
    case welcome = 3
    case keyPackage = 4
  }
}
