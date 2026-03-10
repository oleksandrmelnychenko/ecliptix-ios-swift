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
  private static let keyPackageTTLHours: UInt32 = 168
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
      var cursor = try lastProcessedServerSeq()
      var totalProcessed = 0

      while true {
        let batch = try await fetchPendingEvents(afterServerSeq: cursor, maxEvents: Self.catchUpBatchSize)
        if batch.events.isEmpty {
          break
        }

        var processedEventSeqs: [Int64] = []

        for event in batch.events {
          try await processIncomingEvent(event)
          processedEventSeqs.append(event.serverSeq)
          totalProcessed += 1
        }

        if let lastEvent = batch.events.last {
          try database.setSyncState(
            key: SyncStateRecord.Keys.lastEventId,
            value: String(lastEvent.serverSeq)
          )
          cursor = lastEvent.serverSeq
        }

        await acknowledgeProcessedEventsIfNeeded(processedEventSeqs)
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
    afterServerSeq: Int64,
    maxEvents: UInt32
  ) async throws -> InternalFetchPendingEventsResponse {
    var request = InternalFetchPendingEventsRequest()
    request.deviceID = deviceId
    request.afterSeq = afterServerSeq
    request.maxEvents = maxEvents

    let result = await transport.unary(
      serviceType: .e2eFetchPendingEvents,
      payload: request,
      exchangeType: .dataCenterEphemeralConnect
    )

    switch result {
    case .ok(let envelope):
      return try InternalFetchPendingEventsResponse(serializedBytes: envelope.payload)
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
    let lastServerSeq = (try? lastProcessedServerSeq()) ?? 0
    state = .streaming
    Self.log.info("Event stream started, lastServerSeq=\(lastServerSeq, privacy: .public)")

    var streamRequest = InternalStreamPendingEventsRequest()
    streamRequest.deviceID = deviceId
    streamRequest.afterSeq = lastServerSeq

    let result = await transport.serverStream(
      serviceType: .e2ePendingEventsStream,
      payload: streamRequest,
      exchangeType: .dataCenterEphemeralConnect
    ) { [weak self] envelope in
      guard let self else { return }
      do {
        let event = try InternalPendingEvent(serializedBytes: envelope.payload)
        try await self.processIncomingEvent(event)
        try self.database.setSyncState(
          key: SyncStateRecord.Keys.lastEventId,
          value: String(event.serverSeq)
        )
        await self.acknowledgeProcessedEventsIfNeeded([event.serverSeq])
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

  private func processIncomingEvent(_ event: InternalPendingEvent) async throws {
    switch event.eventType {
    case "group_message":
      try await messageProcessor.processGroupMessage(
        groupId: event.groupID,
        ciphertext: event.payload,
        senderDeviceId: event.senderDevice
      )
    case "group_commit":
      try await messageProcessor.processGroupCommit(
        groupId: event.groupID,
        commitBytes: event.payload
      )
    case "welcome":
      try await processWelcome(event)
    default:
      throw Failure.invalidState(
        "Unknown pending event type \(event.eventType) for seq \(event.serverSeq)")
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
    _ event: InternalPendingEvent
  ) async throws {
    let conversationId = event.hasConversationID ? event.conversationID : nil

    if event.hasTargetKeyPackageHash {
      guard let secrets = await cryptoState.consumeKeyPackageSecrets(
        keyPackageHash: event.targetKeyPackageHash
      ) else {
        Self.log.error(
          "No key package secrets available for targeted Welcome hash=\(event.targetKeyPackageHash.hexString, privacy: .public)"
        )
        throw Failure.cryptoError("No matching key package secrets available for Welcome processing")
      }
      try await messageProcessor.processWelcome(
        welcomeBytes: event.payload,
        senderDeviceId: event.senderDevice,
        identity: identity,
        secrets: secrets,
        conversationId: conversationId
      )
      return
    }

    let candidates = await cryptoState.consumeAllKeyPackageSecretEntries()
    guard !candidates.isEmpty else {
      Self.log.error(
        "No key package secrets available to process Welcome from \(event.senderDevice.hexString, privacy: .public)"
      )
      throw Failure.cryptoError("No key package secrets available for Welcome processing")
    }

    for (index, entry) in candidates.enumerated() {
      do {
        try await messageProcessor.processWelcome(
          welcomeBytes: event.payload,
          senderDeviceId: event.senderDevice,
          identity: identity,
          secrets: entry.secrets,
          conversationId: conversationId
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
    let recipientDevices = try recipientDevices(for: conversationId)

    var request = InternalSendGroupMessageRequest()
    request.groupID = info.groupId
    request.epoch = info.epoch
    request.encryptedPayload = encryptResult.ciphertext
    request.recipientDevices = recipientDevices

    let envelopeBytes = try request.serializedData()
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

  func sendGroupCommit(
    conversationId: Data,
    commitBytes: Data,
    welcomeBytes: Data?,
    welcomeTargets: [InternalWelcomeTarget] = [],
    additionalRecipientDevices: [Data] = []
  ) async throws {
    let info = try await cryptoState.sessionInfo(conversationId: conversationId)
    let recipientDevices = try recipientDevices(
      for: conversationId,
      additionalDevices: additionalRecipientDevices
    )

    var request = InternalSendGroupCommitRequest()
    request.groupID = info.groupId
    request.newEpoch = info.epoch
    request.commitPayload = commitBytes
    request.recipientDevices = recipientDevices
    if let welcome = welcomeBytes {
      request.welcomePayload = welcome
    }
    if info.epoch == 1 {
      var creatorIdentity = InternalCreatorIdentity()
      creatorIdentity.identityEd25519Public = try CryptoEngine.getIdentityEd25519Public(identity)
      creatorIdentity.identityX25519Public = try CryptoEngine.getIdentityX25519Public(identity)
      creatorIdentity.credential = deviceId
      request.creatorIdentity = creatorIdentity
      request.conversationID = conversationId
    }
    if !welcomeTargets.isEmpty {
      request.welcomeTargets = welcomeTargets
    }

    let envelopeBytes = try request.serializedData()
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

  func addMemberToConversation(
    conversationId: Data,
    keyPackageBytes: Data,
    targetDeviceId: Data? = nil
  ) async throws {
    let result = try await cryptoState.addMemberAndPersist(
      conversationId: conversationId,
      keyPackageBytes: keyPackageBytes
    )
    var welcomeTargets: [InternalWelcomeTarget] = []
    var additionalRecipientDevices: [Data] = []
    if let targetDeviceId {
      var target = InternalWelcomeTarget()
      target.recipientDevice = targetDeviceId
      target.targetKeyPackageHash = Data(SHA256.hash(data: keyPackageBytes))
      welcomeTargets = [target]
      additionalRecipientDevices = [targetDeviceId]
    }
    try await sendGroupCommit(
      conversationId: conversationId,
      commitBytes: result.commitBytes,
      welcomeBytes: result.welcomeBytes,
      welcomeTargets: welcomeTargets,
      additionalRecipientDevices: additionalRecipientDevices
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

    var upload = InternalUploadKeyPackagesRequest()
    upload.keyPackages = packages
    upload.ttlHours = Self.keyPackageTTLHours
    upload.senderAccountID = accountId

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
    var request = InternalFetchKeyPackageRequest()
    request.targetDeviceID = targetDeviceId

    let result = await transport.unary(
      serviceType: .e2eFetchKeyPackage,
      payload: request,
      exchangeType: .dataCenterEphemeralConnect
    )

    switch result {
    case .ok(let envelope):
      let response = try InternalFetchKeyPackageResponse(serializedBytes: envelope.payload)
      guard response.found else {
        throw Failure.transportError("fetchKeyPackage: no key package available")
      }
      return response.keyPackage
    case .err(let error):
      throw Failure.transportError("fetchKeyPackage: \(error)")
    }
  }

  func acknowledgeEvents(_ serverSeqs: [Int64]) async throws {
    guard !serverSeqs.isEmpty else { return }

    var ack = InternalAckEventsRequest()
    ack.deviceID = deviceId
    ack.serverSeqs = serverSeqs

    let result = await transport.unary(
      serviceType: .e2eAckEvents,
      payload: ack,
      exchangeType: .dataCenterEphemeralConnect
    )

    if case .err(let error) = result {
      throw Failure.transportError("ackEvents: \(error)")
    }
  }

  private func acknowledgeProcessedEventsIfNeeded(_ serverSeqs: [Int64]) async {
    guard !serverSeqs.isEmpty else { return }
    do {
      try await acknowledgeEvents(serverSeqs)
    } catch {
      Self.log.warning(
        "Failed to acknowledge \(serverSeqs.count) E2E events: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  private func lastProcessedServerSeq() throws -> Int64 {
    guard
      let rawValue = try database.getSyncState(key: SyncStateRecord.Keys.lastEventId),
      !rawValue.isEmpty
    else {
      return 0
    }
    return Int64(rawValue) ?? 0
  }

  private func recipientDevices(
    for conversationId: Data,
    additionalDevices: [Data] = []
  ) throws -> [Data] {
    let storedMembers = try database.fetchMembers(conversationId: conversationId)
      .map(\.deviceId)
      .filter { !$0.isEmpty && $0 != deviceId }
    let merged = storedMembers + additionalDevices.filter { !$0.isEmpty && $0 != deviceId }
    let uniqueDevices = Array(Set(merged)).sorted { $0.lexicographicallyPrecedes($1) }
    guard !uniqueDevices.isEmpty else {
      throw Failure.invalidState(
        "No recipient devices known for conversation \(conversationId.hexString)"
      )
    }
    return uniqueDevices
  }
}
