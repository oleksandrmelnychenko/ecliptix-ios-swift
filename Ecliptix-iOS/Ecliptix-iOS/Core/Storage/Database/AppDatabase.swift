// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixStorage
import Foundation
import GRDB
import os.log

struct AppDatabase: Sendable {

  private let dbPool: DatabasePool

  init(dbPool: DatabasePool) throws {
    self.dbPool = dbPool
    try migrator.migrate(dbPool)
  }

  var reader: any DatabaseReader { dbPool }
  var writer: any DatabaseWriter { dbPool }
}

extension AppDatabase {

  enum DatabaseError: Error {
    case insufficientEncryptionKey(Int)
    case applicationSupportUnavailable
  }

  private static let fileProtection = FileProtectionType.completeUnlessOpen

  static func open(at path: String, encryptionKey: Data) throws -> AppDatabase {
    guard encryptionKey.count >= 32 else {
      throw DatabaseError.insufficientEncryptionKey(encryptionKey.count)
    }

    let dbPool = try SQLCipherDatabaseSupport.openDatabasePool(
      at: path,
      encryptionKey: encryptionKey
    ) { config in
      config.foreignKeysEnabled = true
    }
    let database = try AppDatabase(dbPool: dbPool)
    applyFileProtectionIfPossible(at: path)
    return database
  }

  static func databasePath(accountId: UUID) throws -> String {
    guard
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw DatabaseError.applicationSupportUnavailable
    }

    let dir = appSupport.appendingPathComponent(
      "Ecliptix/\(accountId.uuidString)", isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: dir,
        withIntermediateDirectories: true,
        attributes: [.protectionKey: fileProtection]
      )
    } catch {
      AppLogger.app.error(
        "AppDatabase: failed to create database directory: \(error.localizedDescription, privacy: .public)"
      )
    }

    var url = dir.appendingPathComponent("ecliptix.db")
    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    do {
      try url.setResourceValues(resourceValues)
    } catch {
      AppLogger.app.error(
        "AppDatabase: failed to exclude database from backup: \(error.localizedDescription, privacy: .public)"
      )
    }
    return url.path
  }

  private static func applyFileProtectionIfPossible(at path: String) {
    let fileManager = FileManager.default
    let protectedPaths = [
      URL(fileURLWithPath: path).deletingLastPathComponent().path,
      path,
      "\(path)-wal",
      "\(path)-shm",
    ]

    for candidate in protectedPaths where fileManager.fileExists(atPath: candidate) {
      do {
        try fileManager.setAttributes([.protectionKey: fileProtection], ofItemAtPath: candidate)
      } catch {
        AppLogger.app.error(
          "AppDatabase: failed to apply file protection at \(candidate, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }
}

extension AppDatabase {

  private var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()

    #if DEBUG && targetEnvironment(simulator)
      migrator.eraseDatabaseOnSchemaChange = true
    #endif

    migrator.registerMigration("v1_initial") { db in
      try db.create(table: "device") { t in
        t.primaryKey("deviceId", .blob)
        t.column("userId", .blob).notNull()
        t.column("displayName", .text)
        t.column("deviceType", .integer).notNull()
        t.column("registeredAt", .integer).notNull()
        t.column("isCurrent", .boolean).defaults(to: false)
      }

      try db.create(table: "conversation") { t in
        t.primaryKey("conversationId", .blob)
        t.column("groupId", .blob).notNull().unique()
        t.column("type", .integer).notNull()
        t.column("status", .integer).notNull()
        t.column("title", .text)
        t.column("avatarUrl", .text)
        t.column("conversationDescription", .text)
        t.column("createdAt", .integer).notNull()
        t.column("updatedAt", .integer).notNull()
        t.column("lastMessageAt", .integer)
        t.column("lastMessagePreview", .text)
        t.column("unreadCount", .integer).defaults(to: 0)
        t.column("isPinned", .boolean).defaults(to: false)
        t.column("muteStatus", .integer).defaults(to: 0)
        t.column("isArchived", .boolean).defaults(to: false)
      }

      try db.create(table: "conversationMember") { t in
        t.column("conversationId", .blob).notNull()
          .references("conversation", onDelete: .cascade)
        t.column("membershipId", .blob).notNull()
        t.column("accountId", .blob).notNull()
        t.column("deviceId", .blob).notNull()
        t.column("leafIndex", .integer).notNull()
        t.column("role", .integer).defaults(to: 0)
        t.column("displayName", .text).notNull()
        t.column("profileName", .text)
        t.column("avatarUrl", .text)
        t.column("joinedAt", .integer).notNull()
        t.primaryKey(["conversationId", "deviceId"])
      }

      try db.create(table: "message") { t in
        t.primaryKey("messageId", .blob)
        t.column("conversationId", .blob).notNull()
          .references("conversation", onDelete: .cascade)
        t.column("senderMembershipId", .blob).notNull()
        t.column("senderDeviceId", .blob).notNull()
        t.column("senderDisplayName", .text)
        t.column("contentType", .integer).notNull()
        t.column("textContent", .text)
        t.column("mediaUrl", .text)
        t.column("mediaFilename", .text)
        t.column("mediaMimeType", .text)
        t.column("mediaSizeBytes", .integer)
        t.column("replyToMessageId", .blob)
        t.column("forwardedFromMessageId", .blob)
        t.column("deliveryStatus", .integer).notNull()
        t.column("sentAt", .integer).notNull()
        t.column("receivedAt", .integer).notNull()
        t.column("editedAt", .integer)
        t.column("isDeleted", .boolean).defaults(to: false)
        t.column("isSealed", .boolean).defaults(to: false)
        t.column("sealedHint", .blob)
        t.column("frankingTag", .blob)
        t.column("frankingKey", .blob)
        t.column("ttlSeconds", .integer).defaults(to: 0)
        t.column("expiresAt", .integer)
        t.column("senderLeafIndex", .integer)
        t.column("generation", .integer)
      }
      try db.create(
        index: "idx_message_conversation",
        on: "message",
        columns: ["conversationId", "sentAt"]
      )

      try db.create(table: "messageReaction") { t in
        t.column("messageId", .blob).notNull()
          .references("message", onDelete: .cascade)
        t.column("membershipId", .blob).notNull()
        t.column("emoji", .text).notNull()
        t.column("reactedAt", .integer).notNull()
        t.primaryKey(["messageId", "membershipId", "emoji"])
      }

      try db.create(table: "cryptoSession") { t in
        t.primaryKey("conversationId", .blob)
        t.column("groupId", .blob).notNull()
        t.column("sealedState", .blob).notNull()
        t.column("epoch", .integer).notNull()
        t.column("updatedAt", .integer).notNull()
      }

      try db.create(table: "outbox") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("conversationId", .blob).notNull()
        t.column("payloadType", .integer).notNull()
        t.column("payload", .blob).notNull()
        t.column("createdAt", .integer).notNull()
        t.column("retryCount", .integer).defaults(to: 0)
        t.column("lastAttemptAt", .integer)
      }

      try db.create(table: "syncState") { t in
        t.primaryKey("key", .text)
        t.column("value", .text).notNull()
      }

      try db.create(index: "idx_crypto_session_group", on: "cryptoSession", columns: ["groupId"])
      try db.create(index: "idx_outbox_conversation", on: "outbox", columns: ["conversationId"])
      try db.create(
        index: "idx_conversation_member_membership", on: "conversationMember",
        columns: ["membershipId"])
    }

    migrator.registerMigration("v2_crypto_session_seal_counter") { db in
      try db.alter(table: "cryptoSession") { t in
        t.add(column: "sealCounter", .integer).notNull().defaults(to: 0)
      }
    }

    return migrator
  }
}

extension AppDatabase {

  func saveConversation(_ record: ConversationRecord) throws {
    try dbPool.write { db in
      var record = record
      try record.save(db)
    }
  }

  func deleteConversation(id: Data) throws {
    try dbPool.write { db in
      _ = try ConversationRecord.deleteOne(db, key: id)
    }
  }

  func fetchConversation(id: Data) throws -> ConversationRecord? {
    try dbPool.read { db in
      try ConversationRecord.fetchOne(db, key: id)
    }
  }

  func fetchConversationByGroupId(_ groupId: Data) throws -> ConversationRecord? {
    try dbPool.read { db in
      try ConversationRecord.filter(Column("groupId") == groupId).fetchOne(db)
    }
  }

  func fetchAllConversations() throws -> [ConversationRecord] {
    try dbPool.read { db in
      try ConversationRecord
        .order(Column("lastMessageAt").desc)
        .fetchAll(db)
    }
  }
}

extension AppDatabase {

  func saveMessage(_ record: MessageRecord) throws {
    try dbPool.write { db in
      var record = record
      try record.save(db)
    }
  }

  func fetchMessages(conversationId: Data, limit: Int, beforeSentAt: Int64? = nil) throws
    -> [MessageRecord]
  {
    try dbPool.read { db in
      var request =
        MessageRecord
        .filter(Column("conversationId") == conversationId)
      if let before = beforeSentAt {
        request = request.filter(Column("sentAt") < before)
      }
      return
        try request
        .order(Column("sentAt").desc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func updateMessageStatus(messageId: Data, status: Int) throws {
    try dbPool.write { db in
      if var message = try MessageRecord.fetchOne(db, key: messageId) {
        message.deliveryStatus = status
        try message.update(db)
      }
    }
  }

  func markMessagesExpired(before timestamp: Int64) throws -> Int {
    try dbPool.write { db in
      try MessageRecord
        .filter(Column("expiresAt") != nil && Column("expiresAt") <= timestamp)
        .filter(Column("isDeleted") == false)
        .updateAll(db, Column("isDeleted").set(to: true))
    }
  }
}

extension AppDatabase {

  func saveCryptoSession(_ record: CryptoSessionRecord) throws {
    try dbPool.write { db in
      var record = record
      try record.save(db)
    }
  }

  func fetchCryptoSession(conversationId: Data) throws -> CryptoSessionRecord? {
    try dbPool.read { db in
      try CryptoSessionRecord.fetchOne(db, key: conversationId)
    }
  }

  func fetchCryptoSessionByGroupId(_ groupId: Data) throws -> CryptoSessionRecord? {
    try dbPool.read { db in
      try CryptoSessionRecord.filter(Column("groupId") == groupId).fetchOne(db)
    }
  }

  func deleteCryptoSession(conversationId: Data) throws {
    try dbPool.write { db in
      _ = try CryptoSessionRecord.deleteOne(db, key: conversationId)
    }
  }
}

extension AppDatabase {

  func enqueueOutbox(_ record: OutboxRecord) throws {
    try dbPool.write { db in
      var mutable = record
      try mutable.insert(db)
    }
  }

  func fetchRetriableOutbox(retryCountBelow: Int) throws -> [OutboxRecord] {
    try dbPool.read { db in
      try OutboxRecord
        .filter(Column("retryCount") < retryCountBelow)
        .order(Column("createdAt").asc)
        .fetchAll(db)
    }
  }

  func deleteOutboxEntry(id: Int64) throws {
    try dbPool.write { db in
      _ = try OutboxRecord.deleteOne(db, key: id)
    }
  }

  func incrementOutboxRetry(id: Int64) throws {
    try dbPool.write { db in
      if var entry = try OutboxRecord.fetchOne(db, key: id) {
        entry.retryCount += 1
        entry.lastAttemptAt = Int64(Date().timeIntervalSince1970)
        try entry.update(db)
      }
    }
  }

  func quarantineOutboxEntry(id: Int64, retryCount: Int) throws {
    try dbPool.write { db in
      if var entry = try OutboxRecord.fetchOne(db, key: id) {
        entry.retryCount = retryCount
        entry.lastAttemptAt = Int64(Date().timeIntervalSince1970)
        try entry.update(db)
      }
    }
  }

  func countPendingOutbox() throws -> Int {
    try dbPool.read { db in
      try OutboxRecord.fetchCount(db)
    }
  }

  func countQuarantinedOutbox(retryCountAtLeast: Int) throws -> Int {
    try dbPool.read { db in
      try OutboxRecord
        .filter(Column("retryCount") >= retryCountAtLeast)
        .fetchCount(db)
    }
  }

  func fetchQuarantinedOutbox(retryCountAtLeast: Int, limit: Int) throws -> [OutboxRecord] {
    try dbPool.read { db in
      try OutboxRecord
        .filter(Column("retryCount") >= retryCountAtLeast)
        .order(Column("lastAttemptAt").descNullsLast, Column("createdAt").asc)
        .limit(limit)
        .fetchAll(db)
    }
  }

  func deleteAllOutbox() throws {
    try dbPool.write { db in
      _ = try OutboxRecord.deleteAll(db)
    }
  }
}

extension AppDatabase {

  func getSyncState(key: String) throws -> String? {
    try dbPool.read { db in
      try SyncStateRecord.fetchOne(db, key: key)?.value
    }
  }

  func setSyncState(key: String, value: String) throws {
    try dbPool.write { db in
      try SyncStateRecord(key: key, value: value).save(db)
    }
  }
}

extension AppDatabase {

  func saveConversationMember(_ record: ConversationMemberRecord) throws {
    try dbPool.write { db in
      try record.save(db)
    }
  }

  func fetchMembers(conversationId: Data) throws -> [ConversationMemberRecord] {
    try dbPool.read { db in
      try ConversationMemberRecord
        .filter(Column("conversationId") == conversationId)
        .fetchAll(db)
    }
  }

  func removeMember(conversationId: Data, deviceId: Data) throws {
    try dbPool.write { db in
      _ =
        try ConversationMemberRecord
        .filter(Column("conversationId") == conversationId && Column("deviceId") == deviceId)
        .deleteAll(db)
    }
  }
}

extension AppDatabase {

  func saveDevice(_ record: DeviceRecord) throws {
    try dbPool.write { db in
      try record.save(db)
    }
  }

  func fetchCurrentDevice() throws -> DeviceRecord? {
    try dbPool.read { db in
      try DeviceRecord.filter(Column("isCurrent") == true).fetchOne(db)
    }
  }

  func fetchAllDevices() throws -> [DeviceRecord] {
    try dbPool.read { db in
      try DeviceRecord.fetchAll(db)
    }
  }
}

extension AppDatabase {

  func saveReaction(_ record: MessageReactionRecord) throws {
    try dbPool.write { db in
      try record.save(db)
    }
  }

  func fetchReactions(messageId: Data) throws -> [MessageReactionRecord] {
    try dbPool.read { db in
      try MessageReactionRecord
        .filter(Column("messageId") == messageId)
        .fetchAll(db)
    }
  }
}

extension AppDatabase {

  func updateConversationPreview(
    conversationId: Data,
    lastMessageAt: Int64,
    lastMessagePreview: String?
  ) throws {
    try dbPool.write { db in
      if var conv = try ConversationRecord.fetchOne(db, key: conversationId) {
        conv.lastMessageAt = lastMessageAt
        conv.lastMessagePreview = lastMessagePreview
        conv.updatedAt = Int64(Date().timeIntervalSince1970)
        try conv.update(db)
      }
    }
  }

  func incrementUnreadCount(conversationId: Data) throws {
    try dbPool.write { db in
      try db.execute(
        sql: "UPDATE conversation SET unreadCount = unreadCount + 1 WHERE conversationId = ?",
        arguments: [conversationId]
      )
    }
  }

  func resetUnreadCount(conversationId: Data) throws {
    try dbPool.write { db in
      try db.execute(
        sql: "UPDATE conversation SET unreadCount = 0 WHERE conversationId = ?",
        arguments: [conversationId]
      )
    }
  }
}
