import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class GroupCreationViewModel: Resettable {

  var groupName: String = ""
  var groupDescription: String = ""
  var shieldMode: Bool = false
  var isCreating: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  let memberIds: [Data]

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32

  init(
    memberIds: [Data],
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.memberIds = memberIds
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  var canCreate: Bool {
    !groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  func createGroup() async -> Data? {
    guard canCreate else { return nil }
    guard let currentAccountId else {
      AppLogger.messaging.error("GroupCreation: missing accountId for createGroup")
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return nil
    }

    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("GroupCreation: no membershipId for createGroup")
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return nil
    }

    isCreating = true
    defer { isCreating = false }

    hasError = false
    errorMessage = ""

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.createGroupConversation(
      accountId: currentAccountId,
      membershipId: membershipId.protobufBytes,
      title: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
      description: groupDescription.isEmpty ? nil : groupDescription,
      memberIds: memberIds,
      shieldMode: shieldMode,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      hasError = false
      errorMessage = ""
      return response.conversation.conversationID
    case .err(let rpcError):
      AppLogger.messaging.error(
        "GroupCreation: failed to create group: \(rpcError.logDescription, privacy: .public)")
      hasError = true
      errorMessage = rpcError.userFacingMessage
      return nil
    }
  }

  func resetState() {
    groupName = ""
    groupDescription = ""
    shieldMode = false
    isCreating = false
    hasError = false
    errorMessage = ""
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }
}
