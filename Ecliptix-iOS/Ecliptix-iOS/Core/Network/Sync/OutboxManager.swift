// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

actor OutboxManager {

  private let database: AppDatabase
  private let transport: EventGatewayTransport
  private let deliveryPolicy: OutboxDeliveryPolicy
  private var isFlushing = false

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "OutboxManager"
  )
  private static let quarantineNotificationName = Notification.Name.outboxEntryQuarantined

  private enum SendOutcome: Sendable {
    case sent
    case retryableFailure
    case terminalFailure(String)
  }

  init(
    database: AppDatabase,
    transport: EventGatewayTransport,
    deliveryPolicy: OutboxDeliveryPolicy = .default
  ) {
    self.database = database
    self.transport = transport
    self.deliveryPolicy = deliveryPolicy
  }

  func flushPending() async {
    guard !isFlushing else { return }
    isFlushing = true
    defer { isFlushing = false }

    let entries: [OutboxRecord]
    do {
      entries = try database.fetchRetriableOutbox(retryCountBelow: deliveryPolicy.maxRetryCount)
    } catch {
      Self.log.error(
        "Failed to fetch outbox entries: \(error.localizedDescription, privacy: .public)")
      return
    }

    guard !entries.isEmpty else { return }
    Self.log.debug("Flushing \(entries.count) outbox entries")

    var attemptedEntries = 0
    for entry in entries {
      guard !Task.isCancelled else { break }
      guard attemptedEntries < deliveryPolicy.maxBatchSize else { break }

      guard isReadyForAttempt(entry) else {
        continue
      }

      guard let entryId = entry.id else {
        Self.log.error("Outbox entry missing id, skipping")
        continue
      }

      attemptedEntries += 1
      switch await sendOutboxEntry(entry) {
      case .sent:
        do {
          try database.deleteOutboxEntry(id: entryId)
        } catch {
          Self.log.error(
            "Failed to delete sent outbox entry: \(error.localizedDescription, privacy: .public)")
        }
      case .retryableFailure:
        do {
          try database.incrementOutboxRetry(id: entryId)
          if entry.retryCount + 1 >= deliveryPolicy.maxRetryCount {
            Self.log.error(
              "Outbox entry \(entryId, privacy: .public) exhausted retries and was quarantined for manual recovery"
            )
            postQuarantineNotification(
              entryId: entryId,
              conversationId: entry.conversationId,
              payloadType: entry.payloadType,
              reason: "retry limit exceeded"
            )
          }
        } catch {
          Self.log.error(
            "Failed to increment retry count: \(error.localizedDescription, privacy: .public)")
        }
      case .terminalFailure(let reason):
        do {
          try database.quarantineOutboxEntry(id: entryId, retryCount: deliveryPolicy.maxRetryCount)
          Self.log.error(
            "Outbox entry \(entryId, privacy: .public) quarantined due to terminal failure: \(reason, privacy: .public)"
          )
          postQuarantineNotification(
            entryId: entryId,
            conversationId: entry.conversationId,
            payloadType: entry.payloadType,
            reason: reason
          )
        } catch {
          Self.log.error(
            "Failed to quarantine outbox entry: \(error.localizedDescription, privacy: .public)"
          )
        }
      }
    }
  }

  private func isReadyForAttempt(_ entry: OutboxRecord) -> Bool {
    guard let lastAttempt = entry.lastAttemptAt, entry.retryCount > 0 else {
      return true
    }
    let backoff = deliveryPolicy.backoffDelay(forRetryCount: entry.retryCount)
    let nextAttemptAt = TimeInterval(lastAttempt) + backoff
    return Date().timeIntervalSince1970 >= nextAttemptAt
  }

  private func sendOutboxEntry(_ entry: OutboxRecord) async -> SendOutcome {
    guard let payloadType = OutboxRecord.PayloadType(rawValue: entry.payloadType) else {
      return .terminalFailure("Unknown outbox payload type \(entry.payloadType)")
    }

    let serviceType: RpcServiceType
    switch payloadType {
    case .groupMessage:
      serviceType = .e2eSendGroupMessage
    case .groupCommit:
      serviceType = .e2eSendGroupCommit
    case .welcome:
      serviceType = .e2eSendWelcome
    case .keyPackage:
      serviceType = .e2eUploadKeyPackages
    }

    let result = await transport.unaryRaw(
      serviceType: serviceType,
      rawPayload: entry.payload,
      exchangeType: .dataCenterEphemeralConnect
    )

    switch result {
    case .ok:
      Self.log.debug(
        "Sent outbox entry id=\(entry.id ?? -1), type=\(payloadType.rawValue, privacy: .public)")
      return .sent
    case .err(let error):
      Self.log.warning(
        "Failed to send outbox entry id=\(entry.id ?? -1): \(error, privacy: .public)")
      return .retryableFailure
    }
  }

  func enqueue(
    conversationId: Data,
    payloadType: OutboxRecord.PayloadType,
    payload: Data
  ) throws {
    let entry = OutboxRecord(
      conversationId: conversationId,
      payloadType: payloadType.rawValue,
      payload: payload,
      createdAt: Int64(Date().timeIntervalSince1970),
      retryCount: 0
    )
    try database.enqueueOutbox(entry)
    Self.log.debug(
      "Enqueued outbox entry for conversation \(conversationId.hexString, privacy: .public), type=\(payloadType.rawValue, privacy: .public)"
    )
  }

  func pendingCount() throws -> Int {
    try database.countPendingOutbox()
  }

  func quarantinedCount() throws -> Int {
    try database.countQuarantinedOutbox(retryCountAtLeast: deliveryPolicy.maxRetryCount)
  }

  func quarantinedEntries(limit: Int? = nil) throws -> [OutboxRecord] {
    try database.fetchQuarantinedOutbox(
      retryCountAtLeast: deliveryPolicy.maxRetryCount,
      limit: limit ?? deliveryPolicy.diagnosticsPageSize
    )
  }

  func clearAll() throws {
    try database.deleteAllOutbox()
    Self.log.info("Cleared all outbox entries")
  }

  private func postQuarantineNotification(
    entryId: Int64,
    conversationId: Data,
    payloadType: Int,
    reason: String
  ) {
    NotificationCenter.default.post(
      name: Self.quarantineNotificationName,
      object: nil,
      userInfo: [
        "entryId": entryId,
        "conversationId": conversationId,
        "payloadType": payloadType,
        "reason": reason,
      ]
    )
  }
}

extension Notification.Name {

  static let outboxEntryQuarantined = Notification.Name("com.ecliptix.outboxEntryQuarantined")
}
