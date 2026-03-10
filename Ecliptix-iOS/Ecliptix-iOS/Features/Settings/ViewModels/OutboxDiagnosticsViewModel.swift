// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

@Observable @MainActor
final class OutboxDiagnosticsViewModel {

  struct Entry: Identifiable, Sendable {
    let id: Int64
    let payloadType: String
    let retryCount: Int
    let createdAt: Date
    let lastAttemptAt: Date?
    let payloadSizeBytes: Int
    let conversationIdHex: String
  }

  var isLoading: Bool = false
  var entries: [Entry] = []
  var quarantinedCount: Int = 0
  var errorMessage: String = ""
  var hasError: Bool = false
  var activeAccountId: UUID?

  private let databaseProvider: AccountScopedDatabaseProvider
  private let deliveryPolicy: OutboxDeliveryPolicy
  private var notificationTask: Task<Void, Never>?

  init(
    databaseProvider: AccountScopedDatabaseProvider,
    deliveryPolicy: OutboxDeliveryPolicy = .default
  ) {
    self.databaseProvider = databaseProvider
    self.deliveryPolicy = deliveryPolicy
  }

  deinit {
    notificationTask?.cancel()
  }

  func load() async {
    startObservingIfNeeded()
    await refresh()
  }

  func refresh() async {
    isLoading = true
    defer { isLoading = false }

    activeAccountId = databaseProvider.activeAccountId
    guard let database = databaseProvider.appDatabase else {
      entries = []
      quarantinedCount = 0
      errorMessage = String(localized: "No active account database")
      hasError = true
      return
    }

    do {
      quarantinedCount = try database.countQuarantinedOutbox(
        retryCountAtLeast: deliveryPolicy.maxRetryCount
      )
      entries = try database.fetchQuarantinedOutbox(
        retryCountAtLeast: deliveryPolicy.maxRetryCount,
        limit: deliveryPolicy.diagnosticsPageSize
      ).compactMap(makeEntry(from:))
      hasError = false
      errorMessage = ""
    } catch {
      AppLogger.ui.error(
        "OutboxDiagnostics: failed to load quarantined entries: \(error.localizedDescription, privacy: .public)"
      )
      entries = []
      quarantinedCount = 0
      errorMessage = String(localized: "Failed to load outbox diagnostics")
      hasError = true
    }
  }

  func stopObserving() {
    notificationTask?.cancel()
    notificationTask = nil
  }

  private func startObservingIfNeeded() {
    guard notificationTask == nil else { return }
    notificationTask = Task { [weak self] in
      guard let self else { return }
      let notifications = NotificationCenter.default.notifications(
        named: .outboxEntryQuarantined
      )
      for await _ in notifications {
        guard !Task.isCancelled else { return }
        await self.refresh()
      }
    }
  }

  private func makeEntry(from record: OutboxRecord) -> Entry? {
    guard let id = record.id else { return nil }
    return Entry(
      id: id,
      payloadType: payloadTypeLabel(for: record.payloadType),
      retryCount: record.retryCount,
      createdAt: Date(timeIntervalSince1970: TimeInterval(record.createdAt)),
      lastAttemptAt: record.lastAttemptAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
      payloadSizeBytes: record.payload.count,
      conversationIdHex: record.conversationId.hexString
    )
  }

  private func payloadTypeLabel(for rawValue: Int) -> String {
    guard let payloadType = OutboxRecord.PayloadType(rawValue: rawValue) else {
      return "unknown(\(rawValue))"
    }

    switch payloadType {
    case .groupMessage: return "group_message"
    case .groupCommit: return "group_commit"
    case .welcome: return "welcome"
    case .keyPackage: return "key_package"
    }
  }
}
