// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct SyncStateRecord: Codable, Sendable {
  var key: String
  var value: String
}

extension SyncStateRecord: FetchableRecord, PersistableRecord, TableRecord {
  static let databaseTableName = "syncState"
}

extension SyncStateRecord {
  enum Keys {
    static let lastEventId = "last_event_id"
    static let lastSyncTimestamp = "last_sync_timestamp"
    static let syncVersion = "sync_version"
  }
}
