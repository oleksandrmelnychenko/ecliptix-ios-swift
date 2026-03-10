// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os

@Observable @MainActor
final class CreateChannelViewModel: Resettable {

  static let maxChannelNameLength = 128

  var channelName: String = "" {
    didSet {
      let clamped = String(channelName.prefix(Self.maxChannelNameLength))
      if clamped != channelName {
        channelName = clamped
      }
    }
  }
  var channelDescription: String = ""
  var isPublic: Bool = true
  var adminSignatures: Bool = false
  var isCreating: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32

  init(
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  var canCreate: Bool {
    let trimmedName = channelName.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmedName.isEmpty && trimmedName.count <= Self.maxChannelNameLength
  }

  func createChannel() async -> Data? {
    guard canCreate else { return nil }
    guard let currentAccountId else {
      AppLogger.messaging.error("CreateChannel: missing accountId")
      hasError = true
      errorMessage = String(localized: "Missing account information")
      return nil
    }
    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("CreateChannel: no membershipId")
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return nil
    }

    isCreating = true
    defer { isCreating = false }
    hasError = false
    errorMessage = ""

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.createChannel(
      accountId: currentAccountId,
      membershipId: membershipId.protobufBytes,
      title: channelName.trimmingCharacters(in: .whitespacesAndNewlines),
      description: channelDescription.isEmpty ? nil : channelDescription,
      isPublic: isPublic,
      adminSignatures: adminSignatures,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      return response.conversation.conversationID
    case .err(let rpcError):
      AppLogger.messaging.error(
        "CreateChannel: failed: \(rpcError.logDescription, privacy: .public)")
      hasError = true
      errorMessage = rpcError.userFacingMessage
      return nil
    }
  }

  func resetState() {
    channelName = ""
    channelDescription = ""
    isPublic = true
    adminSignatures = false
    isCreating = false
    hasError = false
    errorMessage = ""
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }
}
