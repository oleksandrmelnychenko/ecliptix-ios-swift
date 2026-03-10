// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import EcliptixProtos
import Foundation
import GRDB
import SwiftProtobuf
import os.log

actor MessageProcessor {

  private let database: AppDatabase
  private let cryptoState: CryptoStateManager

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "MessageProcessor"
  )

  enum Failure: Error, Sendable {
    case decryptionFailed(String)
    case commitProcessingFailed(String)
    case welcomeProcessingFailed(String)
    case conversationNotFound(Data)
    case deserializationFailed(String)
    case databaseError(String)
  }

  init(database: AppDatabase, cryptoState: CryptoStateManager) {
    self.database = database
    self.cryptoState = cryptoState
  }

  func processGroupMessage(
    groupId: Data,
    ciphertext: Data,
    senderDeviceId: Data
  ) async throws {
    let (conversationId, _) = try await cryptoState.loadSessionByGroupId(groupId)

    let decryptResult: GroupDecryptExResult
    do {
      decryptResult = try await cryptoState.decryptExAndPersist(
        conversationId: conversationId,
        ciphertext: ciphertext
      )
    } catch {
      Self.log.error(
        "Decryption failed for group \(groupId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.decryptionFailed(error.localizedDescription)
    }

    let messageRecord = parseAndStoreMessage(
      decryptResult: decryptResult,
      conversationId: conversationId,
      senderDeviceId: senderDeviceId
    )

    if let record = messageRecord {
      do {
        try database.saveMessage(record)
        try database.updateConversationPreview(
          conversationId: conversationId,
          lastMessageAt: record.sentAt,
          lastMessagePreview: record.textContent
        )
        try database.incrementUnreadCount(conversationId: conversationId)
        Self.log.debug(
          "Stored message \(record.messageId.hexString, privacy: .public) in conversation \(conversationId.hexString, privacy: .public)"
        )
      } catch {
        Self.log.error("Failed to store message: \(error.localizedDescription, privacy: .public)")
        throw Failure.databaseError(error.localizedDescription)
      }
    }
  }

  func processGroupCommit(
    groupId: Data,
    commitBytes: Data
  ) async throws {
    let (conversationId, _) = try await cryptoState.loadSessionByGroupId(groupId)

    do {
      try await cryptoState.processCommitAndPersist(
        conversationId: conversationId,
        commitBytes: commitBytes
      )
    } catch {
      Self.log.error(
        "Commit processing failed for group \(groupId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.commitProcessingFailed(error.localizedDescription)
    }

    let info = try await cryptoState.sessionInfo(conversationId: conversationId)
    Self.log.info(
      "Processed commit for group \(groupId.hexString, privacy: .public), new epoch=\(info.epoch)")
  }

  func processWelcome(
    welcomeBytes: Data,
    senderDeviceId: Data,
    identity: ManagedIdentityHandle,
    secrets: ManagedKeyPackageSecrets
  ) async throws {
    let session: ManagedGroupSession
    do {
      session = try await cryptoState.joinSession(
        identity: identity,
        welcomeBytes: welcomeBytes,
        secrets: secrets
      )
    } catch {
      Self.log.error(
        "Failed to join group from welcome: \(error.localizedDescription, privacy: .public)")
      throw Failure.welcomeProcessingFailed(error.localizedDescription)
    }

    let info = try CryptoEngine.groupInfo(session: session)
    let now = Int64(Date().timeIntervalSince1970)
    let existingConversation = try database.fetchConversationByGroupId(info.groupId)
    let conversationId = existingConversation?.conversationId ?? info.groupId

    do {
      try await cryptoState.persistJoinedSession(conversationId: conversationId, session: session)
    } catch {
      Self.log.error(
        "Failed to persist joined session for welcome group \(info.groupId.hexString, privacy: .public): \(error.localizedDescription, privacy: .public)"
      )
      throw Failure.databaseError(error.localizedDescription)
    }

    let conversation = ConversationRecord(
      conversationId: conversationId,
      groupId: info.groupId,
      type: existingConversation?.type ?? 0,
      status: existingConversation?.status ?? 1,
      title: existingConversation?.title,
      avatarUrl: existingConversation?.avatarUrl,
      conversationDescription: existingConversation?.conversationDescription,
      createdAt: existingConversation?.createdAt ?? now,
      updatedAt: now,
      lastMessageAt: existingConversation?.lastMessageAt,
      lastMessagePreview: existingConversation?.lastMessagePreview,
      unreadCount: existingConversation?.unreadCount ?? 0,
      isPinned: existingConversation?.isPinned ?? false,
      muteStatus: existingConversation?.muteStatus ?? 0,
      isArchived: existingConversation?.isArchived ?? false
    )

    do {
      try database.saveConversation(conversation)
    } catch {
      Self.log.error(
        "Failed to save conversation from welcome: \(error.localizedDescription, privacy: .public)")
      throw Failure.databaseError(error.localizedDescription)
    }

    Self.log.info(
      "Joined group \(info.groupId.hexString, privacy: .public) via welcome, epoch=\(info.epoch), members=\(info.memberCount)"
    )
  }

  private func parseAndStoreMessage(
    decryptResult: GroupDecryptExResult,
    conversationId: Data,
    senderDeviceId: Data
  ) -> MessageRecord? {
    let now = Int64(Date().timeIntervalSince1970)
    let isSealed = isSealedContentType(rawValue: decryptResult.contentType)
      || decryptResult.hasSealedPayload
    let ttlSeconds = Int(decryptResult.ttlSeconds)
    let fallbackSentAt = decryptResult.sentTimestamp > 0 ? Int64(decryptResult.sentTimestamp) : now
    let fallbackMessageId = decryptResult.messageId.isEmpty ? nil : decryptResult.messageId
    let fallbackReplyToMessageId = decryptResult.referencedMessageId.isEmpty
      ? nil
      : decryptResult.referencedMessageId

    do {
      let chatMessage = try ProtoChatMessage(serializedBytes: decryptResult.plaintext)
      let messageId =
        chatMessage.messageID.isEmpty
        ? (fallbackMessageId
          ?? deterministicMessageId(
            plaintext: decryptResult.plaintext,
            senderDeviceId: senderDeviceId,
            generation: UInt64(decryptResult.generation)
          ))
        : chatMessage.messageID
      let sentAt = chatMessage.hasSentAt ? chatMessage.sentAt.seconds : fallbackSentAt
      let expiresAt = ttlSeconds > 0 ? sentAt + Int64(ttlSeconds) : nil

      return MessageRecord(
        messageId: messageId,
        conversationId: conversationId,
        senderMembershipId: chatMessage.senderMembershipID,
        senderDeviceId: senderDeviceId,
        senderDisplayName: nil,
        contentType: Int(chatMessage.contentType.rawValue),
        textContent: chatMessage.textContent.isEmpty ? nil : chatMessage.textContent,
        mediaUrl: nil,
        mediaFilename: nil,
        mediaMimeType: nil,
        mediaSizeBytes: nil,
        replyToMessageId: chatMessage.hasReplyToMessageID
          ? chatMessage.replyToMessageID
          : fallbackReplyToMessageId,
        forwardedFromMessageId: chatMessage.hasForwardedFromMessageID
          ? chatMessage.forwardedFromMessageID
          : nil,
        deliveryStatus: MessageRecord.DeliveryStatus.delivered.rawValue,
        sentAt: sentAt,
        receivedAt: now,
        editedAt: nil,
        isDeleted: false,
        isSealed: isSealed,
        sealedHint: nil,
        frankingTag: nil,
        frankingKey: nil,
        ttlSeconds: ttlSeconds,
        expiresAt: expiresAt,
        senderLeafIndex: Int(decryptResult.senderLeafIndex),
        generation: Int64(decryptResult.generation)
      )
    } catch {
      Self.log.warning(
        "Failed to deserialize ChatMessage, storing as raw: \(error.localizedDescription, privacy: .public)"
      )
      let sentAt = fallbackSentAt
      let expiresAt = ttlSeconds > 0 ? sentAt + Int64(ttlSeconds) : nil
      let messageId = fallbackMessageId
        ?? deterministicMessageId(
          plaintext: decryptResult.plaintext,
          senderDeviceId: senderDeviceId,
          generation: UInt64(decryptResult.generation)
        )
      return MessageRecord(
        messageId: messageId,
        conversationId: conversationId,
        senderMembershipId: Data(),
        senderDeviceId: senderDeviceId,
        senderDisplayName: nil,
        contentType: 0,
        textContent: nil,
        mediaUrl: nil,
        mediaFilename: nil,
        mediaMimeType: nil,
        mediaSizeBytes: nil,
        replyToMessageId: fallbackReplyToMessageId,
        forwardedFromMessageId: nil,
        deliveryStatus: MessageRecord.DeliveryStatus.delivered.rawValue,
        sentAt: sentAt,
        receivedAt: now,
        editedAt: nil,
        isDeleted: false,
        isSealed: isSealed,
        sealedHint: nil,
        frankingTag: nil,
        frankingKey: nil,
        ttlSeconds: ttlSeconds,
        expiresAt: expiresAt,
        senderLeafIndex: Int(decryptResult.senderLeafIndex),
        generation: Int64(decryptResult.generation)
      )
    }
  }

  private func isSealedContentType(rawValue: UInt32) -> Bool {
    guard let contentType = ProtoGroupContentType(rawValue: Int(rawValue)) else {
      return false
    }
    switch contentType {
    case .sealed, .sealedDisappearing:
      return true
    default:
      return false
    }
  }

  private func deterministicMessageId(
    plaintext: Data,
    senderDeviceId: Data,
    generation: UInt64
  ) -> Data {
    var material = Data()
    material.append(plaintext)
    material.append(senderDeviceId)
    withUnsafeBytes(of: generation.bigEndian) { material.append(contentsOf: $0) }
    return Data(SHA256.hash(data: material))
  }
}
