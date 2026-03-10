import EcliptixStorage
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

final class AccountScopedDatabaseProvider: @unchecked Sendable {

  static let shared = AccountScopedDatabaseProvider()

  private let lock = NSLock()
  private var currentAccountId: UUID?
  private var _appDatabase: AppDatabase?
  private var _feedDatabase: FeedDatabase?

  private init() {}

  var appDatabase: AppDatabase? {
    lock.withLock { _appDatabase }
  }

  var feedDatabase: FeedDatabase? {
    lock.withLock { _feedDatabase }
  }

  var activeAccountId: UUID? {
    lock.withLock { currentAccountId }
  }

  func activate(accountId: UUID, encryptionKey: Data) throws {
    let appDbPath = try AppDatabase.databasePath(accountId: accountId)
    let appDb = try AppDatabase.open(at: appDbPath, encryptionKey: encryptionKey)

    let feedDirURL = FeedDatabase.directoryURL(accountId: accountId)
    let feedDb = try FeedDatabase.open(at: feedDirURL, encryptionKey: encryptionKey)

    lock.withLock {
      if currentAccountId != nil && currentAccountId != accountId {
        AppLogger.app.info("AccountScopedDB: deactivated previous account")
      }
      currentAccountId = accountId
      _appDatabase = appDb
      _feedDatabase = feedDb
    }

    AppLogger.app.info(
      "AccountScopedDB: activated accountId=\(accountId.uuidString, privacy: .public)"
    )
  }

  func deactivate() {
    lock.withLock {
      _appDatabase = nil
      _feedDatabase = nil
      let previousId = currentAccountId?.uuidString ?? "none"
      currentAccountId = nil
      AppLogger.app.info("AccountScopedDB: deactivated accountId=\(previousId, privacy: .public)")
    }
  }
}
