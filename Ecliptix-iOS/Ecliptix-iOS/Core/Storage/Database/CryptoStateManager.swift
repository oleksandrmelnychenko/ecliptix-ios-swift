// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import GRDB
import os.log

actor CryptoStateManager {

  private static let sealedMessageHint = Data("sealed".utf8)

  private let database: AppDatabase
  private let sealKey: Data
  private let identity: ManagedIdentityHandle
  private var sessionCache: [Data: ManagedGroupSession] = [:]
  private var sessionAccessTime: [Data: UInt64] = [:]
  private var accessCounter: UInt64 = 0
  private var groupIdToConversationId: [Data: Data] = [:]
  private static let maxCacheSize = 50

  private var pendingKeyPackageSecrets: [Data: ManagedKeyPackageSecrets] = [:]
  private var sealCounters: [Data: UInt64] = [:]

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "CryptoStateManager"
  )

  enum Failure: Error, Sendable {
    case sessionNotFound(conversationId: Data)
    case serializationFailed(String)
    case deserializationFailed(String)
    case databaseError(String)
    case invalidSealKey

    var localizedDescription: String {
      switch self {
      case .sessionNotFound(let id):
        return "Crypto session not found for conversation \(id.hexString)"
      case .serializationFailed(let msg):
        return "Serialization failed: \(msg)"
      case .deserializationFailed(let msg):
        return "Deserialization failed: \(msg)"
      case .databaseError(let msg):
        return "Database error: \(msg)"
      case .invalidSealKey:
        return "Invalid seal key"
      }
    }
  }

  init(database: AppDatabase, sealKey: Data, identity: ManagedIdentityHandle) throws {
    guard sealKey.count == CryptoEngine.sealKeyLength else {
      throw Failure.invalidSealKey
    }
    self.database = database
    self.sealKey = sealKey
    self.identity = identity
    Self.log.info("CryptoStateManager initialized")
  }

  func loadSession(conversationId: Data) throws -> ManagedGroupSession {
    if let cached = sessionCache[conversationId] {
      touchAccessOrder(conversationId)
      return cached
    }

    guard let record = try database.fetchCryptoSession(conversationId: conversationId) else {
      throw Failure.sessionNotFound(conversationId: conversationId)
    }

    let session: ManagedGroupSession
    do {
      let minCounter = UInt64(bitPattern: record.sealCounter)
      let (deserialized, embeddedCounter) = try CryptoEngine.groupDeserialize(
        sealedState: record.sealedState,
        sealKey: sealKey,
        identity: identity,
        minExternalCounter: minCounter
      )
      session = deserialized
      sealCounters[conversationId] = embeddedCounter
    } catch {
      Self.log.error(
        "Failed to deserialize session for \(conversationId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.deserializationFailed(error.localizedDescription)
    }

    cacheSession(conversationId: conversationId, session: session)
    Self.log.debug(
      "Loaded crypto session for conversation \(conversationId.hexString, privacy: .public), epoch=\(record.epoch)"
    )
    return session
  }

  func loadSessionByGroupId(_ groupId: Data) throws -> (
    conversationId: Data, session: ManagedGroupSession
  ) {
    if let convId = groupIdToConversationId[groupId],
      let cached = sessionCache[convId]
    {
      touchAccessOrder(convId)
      return (convId, cached)
    }

    guard let record = try database.fetchCryptoSessionByGroupId(groupId) else {
      throw Failure.sessionNotFound(conversationId: groupId)
    }

    let session: ManagedGroupSession
    do {
      let minCounter = UInt64(bitPattern: record.sealCounter)
      let (deserialized, embeddedCounter) = try CryptoEngine.groupDeserialize(
        sealedState: record.sealedState,
        sealKey: sealKey,
        identity: identity,
        minExternalCounter: minCounter
      )
      session = deserialized
      sealCounters[record.conversationId] = embeddedCounter
    } catch {
      Self.log.error(
        "Failed to deserialize session for groupId \(groupId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.deserializationFailed(error.localizedDescription)
    }

    cacheSession(conversationId: record.conversationId, session: session)
    return (record.conversationId, session)
  }

  func persistSession(conversationId: Data, session: ManagedGroupSession) throws {
    let nextCounter = (sealCounters[conversationId] ?? 0) + 1
    let sealedState: Data
    do {
      sealedState = try CryptoEngine.groupSerialize(
        session: session,
        sealKey: sealKey,
        externalCounter: nextCounter
      )
    } catch {
      Self.log.error(
        "Failed to serialize session for \(conversationId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.serializationFailed(error.localizedDescription)
    }

    let info = try CryptoEngine.groupInfo(session: session)
    let record = CryptoSessionRecord(
      conversationId: conversationId,
      groupId: info.groupId,
      sealedState: sealedState,
      epoch: Int64(info.epoch),
      updatedAt: Int64(Date().timeIntervalSince1970),
      sealCounter: Int64(bitPattern: nextCounter)
    )

    do {
      try database.saveCryptoSession(record)
    } catch {
      Self.log.error(
        "Failed to save crypto session to DB: \(error.localizedDescription, privacy: .public)")
      throw Failure.databaseError(error.localizedDescription)
    }

    sealCounters[conversationId] = nextCounter
    cacheSession(conversationId: conversationId, session: session)
    Self.log.debug(
      "Persisted crypto session for \(conversationId.hexString, privacy: .public), epoch=\(info.epoch)"
    )
  }

  func joinSession(
    identity: ManagedIdentityHandle,
    welcomeBytes: Data,
    secrets: ManagedKeyPackageSecrets
  ) throws -> ManagedGroupSession {
    try CryptoEngine.groupJoin(
      identity: identity,
      welcomeBytes: welcomeBytes,
      secrets: secrets
    )
  }

  func persistJoinedSession(
    conversationId: Data,
    session: ManagedGroupSession
  ) throws {
    try persistSession(conversationId: conversationId, session: session)
  }

  func encryptAndPersist(
    conversationId: Data,
    plaintext: Data
  ) throws -> GroupEncryptResult {
    let session = try loadSession(conversationId: conversationId)
    let result = try CryptoEngine.groupEncrypt(session: session, plaintext: plaintext)
    try persistSession(conversationId: conversationId, session: session)
    return result
  }

  func encryptForSessionPolicyAndPersist(
    conversationId: Data,
    plaintext: Data
  ) throws -> GroupEncryptResult {
    let session = try loadSession(conversationId: conversationId)
    let ciphertext: Data

    if try CryptoEngine.groupIsShielded(session: session) {
      ciphertext = try CryptoEngine.groupEncryptSealed(
        session: session,
        plaintext: plaintext,
        hint: Self.sealedMessageHint
      )
    } else {
      ciphertext = try CryptoEngine.groupEncrypt(session: session, plaintext: plaintext).ciphertext
    }

    try persistSession(conversationId: conversationId, session: session)
    return GroupEncryptResult(ciphertext: ciphertext)
  }

  func decryptAndPersist(
    conversationId: Data,
    ciphertext: Data
  ) throws -> GroupDecryptResult {
    let session = try loadSession(conversationId: conversationId)
    let result = try CryptoEngine.groupDecrypt(session: session, ciphertext: ciphertext)
    try persistSession(conversationId: conversationId, session: session)
    return result
  }

  func decryptExAndPersist(
    conversationId: Data,
    ciphertext: Data
  ) throws -> GroupDecryptExResult {
    let session = try loadSession(conversationId: conversationId)
    let result = try CryptoEngine.groupDecryptEx(session: session, ciphertext: ciphertext)
    try persistSession(conversationId: conversationId, session: session)
    return result
  }

  func processCommitAndPersist(
    conversationId: Data,
    commitBytes: Data
  ) throws {
    let session = try loadSession(conversationId: conversationId)
    try CryptoEngine.groupProcessCommit(session: session, commitBytes: commitBytes)
    try persistSession(conversationId: conversationId, session: session)
    let info = try CryptoEngine.groupInfo(session: session)
    Self.log.info(
      "Processed commit for \(conversationId.hexString, privacy: .public), new epoch=\(info.epoch)")
  }

  func addMemberAndPersist(
    conversationId: Data,
    keyPackageBytes: Data
  ) throws -> GroupAddMemberResult {
    let session = try loadSession(conversationId: conversationId)
    let result = try CryptoEngine.groupAddMember(session: session, keyPackageBytes: keyPackageBytes)
    try persistSession(conversationId: conversationId, session: session)
    return result
  }

  func removeMemberAndPersist(
    conversationId: Data,
    leafIndex: UInt32
  ) throws -> Data {
    let session = try loadSession(conversationId: conversationId)
    let commitBytes = try CryptoEngine.groupRemoveMember(session: session, leafIndex: leafIndex)
    try persistSession(conversationId: conversationId, session: session)
    return commitBytes
  }

  func updateAndPersist(conversationId: Data) throws -> Data {
    let session = try loadSession(conversationId: conversationId)
    let commitBytes = try CryptoEngine.groupUpdate(session: session)
    try persistSession(conversationId: conversationId, session: session)
    return commitBytes
  }

  func storeKeyPackageSecrets(keyPackageHash: Data, secrets: ManagedKeyPackageSecrets) {
    pendingKeyPackageSecrets[keyPackageHash] = secrets
    Self.log.debug(
      "Stored key package secrets, hash=\(keyPackageHash.hexString, privacy: .public), total=\(self.pendingKeyPackageSecrets.count)"
    )
  }

  func consumeKeyPackageSecrets(keyPackageHash: Data) -> ManagedKeyPackageSecrets? {
    let secrets = pendingKeyPackageSecrets.removeValue(forKey: keyPackageHash)
    if secrets != nil {
      Self.log.debug(
        "Consumed key package secrets for hash=\(keyPackageHash.hexString, privacy: .public)")
    }
    return secrets
  }

  func consumeAnyKeyPackageSecrets() -> ManagedKeyPackageSecrets? {
    guard let (hash, secrets) = pendingKeyPackageSecrets.first else { return nil }
    pendingKeyPackageSecrets.removeValue(forKey: hash)
    Self.log.debug(
      "Consumed first available key package secrets, hash=\(hash.hexString, privacy: .public), remaining=\(self.pendingKeyPackageSecrets.count)"
    )
    return secrets
  }

  func consumeAllKeyPackageSecrets() -> [ManagedKeyPackageSecrets] {
    let all = Array(pendingKeyPackageSecrets.values)
    pendingKeyPackageSecrets.removeAll()
    Self.log.debug("Consumed all \(all.count) key package secrets")
    return all
  }

  func consumeAllKeyPackageSecretEntries() -> [(hash: Data, secrets: ManagedKeyPackageSecrets)] {
    let all = pendingKeyPackageSecrets.map { ($0.key, $0.value) }
    pendingKeyPackageSecrets.removeAll()
    Self.log.debug("Consumed all \(all.count) key package secret entries")
    return all
  }

  func restoreKeyPackageSecrets(_ entries: [(hash: Data, secrets: ManagedKeyPackageSecrets)]) {
    guard !entries.isEmpty else { return }
    for entry in entries {
      pendingKeyPackageSecrets[entry.hash] = entry.secrets
    }
    Self.log.debug(
      "Restored \(entries.count) unused key package secret entries, total=\(self.pendingKeyPackageSecrets.count)"
    )
  }

  func destroyAllKeyPackageSecrets() {
    for (_, secrets) in pendingKeyPackageSecrets {
      secrets.destroy()
    }
    pendingKeyPackageSecrets.removeAll()
    Self.log.debug("Destroyed all pending key package secrets")
  }

  private func touchAccessOrder(_ conversationId: Data) {
    accessCounter += 1
    sessionAccessTime[conversationId] = accessCounter
  }

  private func cacheSession(conversationId: Data, session: ManagedGroupSession) {
    sessionCache[conversationId] = session
    if let info = try? CryptoEngine.groupInfo(session: session) {
      groupIdToConversationId[info.groupId] = conversationId
    }
    touchAccessOrder(conversationId)

    while sessionCache.count > Self.maxCacheSize {
      guard let oldest = sessionAccessTime.min(by: { $0.value < $1.value })?.key else { break }
      sessionAccessTime.removeValue(forKey: oldest)
      sealCounters.removeValue(forKey: oldest)
      if let evicted = sessionCache.removeValue(forKey: oldest) {
        evicted.destroy()
        Self.log.debug("LRU evicted session for \(oldest.hexString, privacy: .public)")
      }
    }
  }

  func evictSession(conversationId: Data) {
    sessionAccessTime.removeValue(forKey: conversationId)
    sealCounters.removeValue(forKey: conversationId)
    groupIdToConversationId = groupIdToConversationId.filter { $0.value != conversationId }
    if let session = sessionCache.removeValue(forKey: conversationId) {
      session.destroy()
      Self.log.debug("Evicted cached session for \(conversationId.hexString, privacy: .public)")
    }
  }

  func deleteSession(conversationId: Data) throws {
    evictSession(conversationId: conversationId)
    try database.deleteCryptoSession(conversationId: conversationId)
    Self.log.info("Deleted crypto session for \(conversationId.hexString, privacy: .public)")
  }

  func evictAllCachedSessions() {
    for (_, session) in sessionCache {
      session.destroy()
    }
    sessionCache.removeAll()
    sessionAccessTime.removeAll()
    sealCounters.removeAll()
    groupIdToConversationId.removeAll()
    destroyAllKeyPackageSecrets()
    Self.log.info("Evicted all cached crypto sessions and key package secrets")
  }

  func sessionExists(conversationId: Data) -> Bool {
    if sessionCache[conversationId] != nil { return true }
    return (try? database.fetchCryptoSession(conversationId: conversationId)) != nil
  }

  func sessionInfo(conversationId: Data) throws -> GroupSessionInfo {
    let session = try loadSession(conversationId: conversationId)
    return try CryptoEngine.groupInfo(session: session)
  }
}
