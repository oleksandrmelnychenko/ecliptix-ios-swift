// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB

struct CryptoSessionRecord: Codable, Sendable {
  var conversationId: Data
  var groupId: Data
  var sealedState: Data
  var epoch: Int64
  var updatedAt: Int64
  var sealCounter: Int64
}

extension CryptoSessionRecord: FetchableRecord, MutablePersistableRecord, TableRecord {
  static let databaseTableName = "cryptoSession"
}
