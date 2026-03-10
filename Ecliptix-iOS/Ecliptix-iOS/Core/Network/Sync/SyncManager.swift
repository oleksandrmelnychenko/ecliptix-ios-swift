// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import EcliptixProtos
import Foundation
import GRDB
import SwiftProtobuf
import os.log

actor SyncManager {

  enum State: Sendable {
    case idle
    case connecting
    case syncing
    case streaming
    case disconnected(retryAt: Date)
    case failed(String)
  }

  enum Failure: Error, Sendable {
    case notInitialized
    case transportError(String)
    case cryptoError(String)
    case databaseError(String)
    case invalidState(String)
    case catchUpFailed(String)
  }

  private let transport: EventGatewayTransport
  private let database: AppDatabase
  private let cryptoState: CryptoStateManager
  private let messageProcessor: MessageProcessor
  private let outboxManager: OutboxManager
  private let identity: ManagedIdentityHandle
  private let deviceId: Data
  private let reconnectPolicy: StreamReconnectPolicy
  let accountId: Data

  private(set) var state: State = .idle
  private var streamTask: Task<Void, Never>?
  private var outboxFlushTask: Task<Void, Never>?
  private var retryCount: Int = 0

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "SyncManager"
  )
  private static let catchUpBatchSize: UInt32 = 100
  private static let outboxFlushInterval: TimeInterval = 5.0

  init(
    transport: EventGatewayTransport,
    database: AppDatabase,
    cryptoState: CryptoStateManager,
    identity: ManagedIdentityHandle,
    deviceId: Data,
    accountId: Data,
    reconnectPolicy: StreamReconnectPolicy = .default,
    outboxDeliveryPolicy: OutboxDeliveryPolicy = .default
  ) {
    self.transport = transport
    self.database = database
    self.cryptoState = cryptoState
    self.identity = identity
    self.deviceId = deviceId
    self.reconnectPolicy = reconnectPolicy
    self.accountId = accountId
    self.messageProcessor = MessageProcessor(
      database: database,
      cryptoState: cryptoState
    )
    self.outboxManager = OutboxManager(
      database: database,
      transport: transport,
      deliveryPolicy: outboxDeliveryPolicy
    )
  }

  func start() async {
    guard case .idle = state else {
      Self.log.warning(
        "SyncManager.start() called in state \(String(describing: self.state), privacy: .public)")
      return
    }

    Self.log.info("SyncManager starting")
    state = .connecting

    await performCatchUp()
    guard !isFailureState else { return }
    startEventStream()
    startOutboxFlush()
  }

  func stop() {
    Self.log.info("SyncManager stopping")
    streamTask?.cancel()
    streamTask = nil
    outboxFlushTask?.cancel()
    outboxFlushTask = nil
    state = .idle
    retryCount = 0
  }

  private func performCatchUp() async {
    state = .syncing
    Self.log.info("Starting catch-up sync")

    do {
      let lastEventId = try database.getSyncState(key: SyncStateRecord.Keys.lastEventId) ?? ""
      var cursor = lastEventId
      var totalProcessed = 0

      while true {
        let batch = try await fetchPendingEvents(
          afterEventId: cursor, maxEvents: Self.catchUpBatchSize)
        if batch.events.isEmpty {
          break
        }

        var processedEventIDs: [String] = []

        for event in batch.events {
          try await processIncomingEvent(event)
          processedEventIDs.append(event.eventID)
          totalProcessed += 1
        }

        if let lastEvent = batch.events.last {
          try database.setSyncState(
            key: SyncStateRecord.Keys.lastEventId,
            value: lastEvent.eventID
          )
        }

        cursor = batch.nextCursor
        await acknowledgeProcessedEventsIfNeeded(processedEventIDs)
        if !batch.hasMore_p {
          break
        }
      }

      try database.setSyncState(
        key: SyncStateRecord.Keys.lastSyncTimestamp,
        value: String(Int64(Date().timeIntervalSince1970))
      )

      Self.log.info("Catch-up sync complete: processed \(totalProcessed) events")
      retryCount = 0
    } catch {
      Self.log.error("Catch-up sync failed: \(error.localizedDescription, privacy: .public)")
      state = .failed(error.localizedDescription)
    }
  }

  private func fetchPendingEvents(
    afterEventId: String,
    maxEvents: UInt32
  ) async throws -> FetchPendingEventsResponse {
    var request = FetchPendingEventsRequest()
    request.deviceID = deviceId
    request.lastEventID = afterEventId
    request.maxEvents = maxEvents

    let result = await transport.unary(
      serviceType: .e2eFetchPendingEvents,
      payload: request,
      exchangeType: .dataCenterEphemeralConnect
    )

    switch result {
    case .ok(let envelope):
      return try FetchPendingEventsResponse(serializedBytes: envelope.payload)
    case .err(let error):
      throw Failure.transportError("fetchPendingEvents: \(error)")
    }
  }

  private func startEventStream() {
    streamTask?.cancel()
    streamTask = Task { [weak self] in
      guard let self else { return }
      await self.runEventStream()
    }
  }

  private func runEventStream() async {
    let lastEventId = (try? database.getSyncState(key: SyncStateRecord.Keys.lastEventId)) ?? ""
    state = .streaming
    Self.log.info("Event stream started, lastEventId=\(lastEventId, privacy: .public)")

    var streamRequest = FetchPendingEventsRequest()
    streamRequest.deviceID = deviceId
    streamRequest.lastEventID = lastEventId
    streamRequest.maxEvents = 0

    let result = await transport.serverStream(
      serviceType: .e2ePendingEventsStream,
      payload: streamRequest,
      exchangeType: .dataCenterEphemeralConnect
    ) { [weak self] envelope in
      guard let self else { return }
      do {
        let event = try PendingEvent(serializedBytes: envelope.payload)
        try await self.processIncomingEvent(event)
        try self.database.setSyncState(
          key: SyncStateRecord.Keys.lastEventId,
          value: event.eventID
        )
        await self.acknowledgeProcessedEventsIfNeeded([event.eventID])
      } catch {
        await self.handleStreamProcessingFailure(error)
      }
    }

    if case .err(let error) = result {
      Self.log.warning("Event stream disconnected: \(error, privacy: .public)")
    }

    guard !Task.isCancelled else { return }
    await scheduleReconnect()
  }

  private func scheduleReconnect() async {
    guard retryCount < reconnectPolicy.maxRetryCount else {
      state = .failed("Max retry count exceeded")
      Self.log.error("Max retry count exceeded, giving up")
      return
    }

    retryCount += 1
    let totalDelay = reconnectPolicy.delay(forAttempt: retryCount)
    let retryDate = Date().addingTimeInterval(totalDelay)
    state = .disconnected(retryAt: retryDate)

    Self.log.info(
      "Reconnecting in \(totalDelay, format: .fixed(precision: 1))s (attempt \(self.retryCount))")
    try? await Task.sleep(for: .seconds(totalDelay))

    guard !Task.isCancelled else { return }

    await performCatchUp()
    guard !isFailureState else { return }
    startEventStream()
  }

  private var isFailureState: Bool {
    if case .failed = state {
      return true
    }
    return false
  }

  private func processIncomingEvent(_ event: PendingEvent) async throws {
    guard event.hasEnvelope else {
      throw Failure.invalidState("Pending event \(event.eventID) missing envelope")
    }

    let envelope = event.envelope
    let payloadType = envelope.payloadType

    switch payloadType {
    case .cryptoPayloadGroupMessage:
      try await messageProcessor.processGroupMessage(
        groupId: envelope.groupID,
        ciphertext: envelope.encryptedPayload,
        senderDeviceId: envelope.senderDeviceID
      )
    case .cryptoPayloadGroupCommit:
      try await messageProcessor.processGroupCommit(
        groupId: envelope.groupID,
        commitBytes: envelope.encryptedPayload
      )
    case .cryptoPayloadWelcome:
      let candidates = await cryptoState.consumeAllKeyPackageSecretEntries()
      guard !candidates.isEmpty else {
        Self.log.error(
          "No key package secrets available to process Welcome from \(envelope.senderDeviceID.hexString, privacy: .public)"
        )
        throw Failure.cryptoError("No key package secrets available for Welcome processing")
      }
      try await processWelcome(
        welcomeBytes: envelope.encryptedPayload,
        senderDeviceId: envelope.senderDeviceID,
        candidates: candidates
      )
    case .cryptoPayloadKeyPackage:
      throw Failure.invalidState(
        "Unsupported pending event payload type \(payloadType.rawValue) for event \(event.eventID)"
      )
    case .cryptoPayloadPrekeyBundle:
      throw Failure.invalidState(
        "Unsupported pending event payload type \(payloadType.rawValue) for event \(event.eventID)"
      )
    default:
      throw Failure.invalidState(
        "Unknown pending event payload type \(payloadType.rawValue) for event \(event.eventID)")
    }
  }

  private func handleStreamProcessingFailure(_ error: Error) {
    let message = error.localizedDescription
    Self.log.error("Failed to process stream event: \(message, privacy: .public)")
    state = .failed(message)
    streamTask?.cancel()
  }

  private func startOutboxFlush() {
    outboxFlushTask?.cancel()
    outboxFlushTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(Self.outboxFlushInterval))
        guard !Task.isCancelled else { return }
        await self.outboxManager.flushPending()
      }
    }
  }

  private func processWelcome(
    welcomeBytes: Data,
    senderDeviceId: Data,
    candidates: [(hash: Data, secrets: ManagedKeyPackageSecrets)]
  ) async throws {
    for (index, entry) in candidates.enumerated() {
      do {
        try await messageProcessor.processWelcome(
          welcomeBytes: welcomeBytes,
          senderDeviceId: senderDeviceId,
          identity: identity,
          secrets: entry.secrets
        )
        let unused = Array(candidates.dropFirst(index + 1))
        await cryptoState.restoreKeyPackageSecrets(unused)
        return
      } catch let error as MessageProcessor.Failure {
        switch error {
        case .welcomeProcessingFailed:
          Self.log.warning(
            "Welcome processing failed for key package hash=\(entry.hash.hexString, privacy: .public), trying next candidate"
          )
          continue
        default:
          let unused = Array(candidates.dropFirst(index + 1))
          await cryptoState.restoreKeyPackageSecrets(unused)
          throw error
        }
      } catch {
        let unused = Array(candidates.dropFirst(index + 1))
        await cryptoState.restoreKeyPackageSecrets(unused)
        throw error
      }
    }

    throw Failure.cryptoError("No matching key package secrets available for Welcome processing")
  }

  func sendGroupMessage(conversationId: Data, plaintext: Data) async throws {
    let encryptResult = try await cryptoState.encryptForSessionPolicyAndPersist(
      conversationId: conversationId,
      plaintext: plaintext
    )

    let info = try await cryptoState.sessionInfo(conversationId: conversationId)
    _ = try database.fetchConversation(id: conversationId)

    var envelope = CryptoEnvelope()
    envelope.senderDeviceID = deviceId
    envelope.payloadType = .cryptoPayloadGroupMessage
    envelope.encryptedPayload = encryptResult.ciphertext
    envelope.groupID = info.groupId
    envelope.epoch = info.epoch
    envelope.senderLeafIndex = info.myLeafIndex

    let envelopeBytes = try envelope.serializedData()
    let outboxEntry = OutboxRecord(
      conversationId: conversationId,
      payloadType: OutboxRecord.PayloadType.groupMessage.rawValue,
      payload: envelopeBytes,
      createdAt: Int64(Date().timeIntervalSince1970),
      retryCount: 0
    )
    try database.enqueueOutbox(outboxEntry)

    await outboxManager.flushPending()
  }

  func sendGroupCommit(conversationId: Data, commitBytes: Data, welcomeBytes: Data?) async throws {
    let info = try await cryptoState.sessionInfo(conversationId: conversationId)

    var commitEnvelope = GroupCommitEnvelope()
    commitEnvelope.groupID = info.groupId
    commitEnvelope.newEpoch = info.epoch
    commitEnvelope.commitBytes = commitBytes
    commitEnvelope.committerDeviceID = deviceId
    if let welcome = welcomeBytes {
      commitEnvelope.welcomeBytes = welcome
    }

    let envelopeBytes = try commitEnvelope.serializedData()
    let outboxEntry = OutboxRecord(
      conversationId: conversationId,
      payloadType: OutboxRecord.PayloadType.groupCommit.rawValue,
      payload: envelopeBytes,
      createdAt: Int64(Date().timeIntervalSince1970),
      retryCount: 0
    )
    try database.enqueueOutbox(outboxEntry)

    await outboxManager.flushPending()
  }

  func addMemberToConversation(conversationId: Data, keyPackageBytes: Data) async throws {
    let result = try await cryptoState.addMemberAndPersist(
      conversationId: conversationId,
      keyPackageBytes: keyPackageBytes
    )
    try await sendGroupCommit(
      conversationId: conversationId,
      commitBytes: result.commitBytes,
      welcomeBytes: result.welcomeBytes
    )
    Self.log.info("Added member to conversation \(conversationId.hexString, privacy: .public)")
  }

  func removeMemberFromConversation(conversationId: Data, leafIndex: UInt32) async throws {
    let commitBytes = try await cryptoState.removeMemberAndPersist(
      conversationId: conversationId,
      leafIndex: leafIndex
    )
    try await sendGroupCommit(
      conversationId: conversationId,
      commitBytes: commitBytes,
      welcomeBytes: nil
    )
    Self.log.info(
      "Removed member leaf=\(leafIndex) from conversation \(conversationId.hexString, privacy: .public)"
    )
  }

  func uploadKeyPackages(count: Int = 10) async throws {
    var packages: [Data] = []
    var secretsByHash: [(hash: Data, secrets: ManagedKeyPackageSecrets)] = []
    packages.reserveCapacity(count)
    secretsByHash.reserveCapacity(count)

    for _ in 0..<count {
      let (kp, secrets) = try CryptoEngine.generateKeyPackage(
        identity: identity,
        credential: deviceId
      )
      let hash = Data(SHA256.hash(data: kp))
      packages.append(kp)
      secretsByHash.append((hash: hash, secrets: secrets))
    }

    var upload = KeyPackageUpload()
    upload.deviceID = deviceId
    upload.keyPackages = packages

    let result = await transport.unary(
      serviceType: .e2eUploadKeyPackages,
      payload: upload,
      exchangeType: .dataCenterEphemeralConnect
    )

    if case .err(let error) = result {
      for entry in secretsByHash {
        entry.secrets.destroy()
      }
      throw Failure.transportError("uploadKeyPackages: \(error)")
    }

    for entry in secretsByHash {
      await cryptoState.storeKeyPackageSecrets(
        keyPackageHash: entry.hash,
        secrets: entry.secrets
      )
    }

    Self.log.info("Uploaded \(count) key packages and stored their secrets")
  }

  func fetchKeyPackage(targetDeviceId: Data) async throws -> Data {
    var request = KeyPackageFetchRequest()
    request.targetDeviceID = targetDeviceId

    let result = await transport.unary(
      serviceType: .e2eFetchKeyPackage,
      payload: request,
      exchangeType: .dataCenterEphemeralConnect
    )

    switch result {
    case .ok(let envelope):
      let response = try KeyPackageFetchResponse(serializedBytes: envelope.payload)
      return response.keyPackage
    case .err(let error):
      throw Failure.transportError("fetchKeyPackage: \(error)")
    }
  }

  func acknowledgeEvents(_ eventIds: [String]) async throws {
    guard !eventIds.isEmpty else { return }

    var ack = AckEventsRequest()
    ack.deviceID = deviceId
    ack.eventIds = eventIds

    let result = await transport.unary(
      serviceType: .e2eAckEvents,
      payload: ack,
      exchangeType: .dataCenterEphemeralConnect
    )

    if case .err(let error) = result {
      throw Failure.transportError("ackEvents: \(error)")
    }
  }

  private func acknowledgeProcessedEventsIfNeeded(_ eventIds: [String]) async {
    guard !eventIds.isEmpty else { return }
    do {
      try await acknowledgeEvents(eventIds)
    } catch {
      Self.log.warning(
        "Failed to acknowledge \(eventIds.count) E2E events: \(error.localizedDescription, privacy: .public)"
      )
    }
  }
}
