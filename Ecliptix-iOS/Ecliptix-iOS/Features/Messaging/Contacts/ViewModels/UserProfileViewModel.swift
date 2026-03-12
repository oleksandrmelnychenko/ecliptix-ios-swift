import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class ProfileViewModel: Resettable {

  var displayName: String = ""
  var handle: String = ""
  var avatarUrl: String?
  var isLoading: Bool = false
  var isBlocked: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> ConnectId
  let membershipId: Data
  private var resolvedMembershipId: Data?

  /// Returns the resolved membershipId from contact lookup, falling back to the init-provided id.
  private var effectiveMembershipId: Data {
    resolvedMembershipId ?? membershipId
  }

  private let fallbackDisplayName: String?
  private let fallbackHandle: String?

  init(
    membershipId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> ConnectId,
    fallbackDisplayName: String? = nil,
    fallbackHandle: String? = nil
  ) {
    self.membershipId = membershipId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
    self.fallbackDisplayName = fallbackDisplayName
    self.fallbackHandle = fallbackHandle
  }

  func loadProfile() async {
    isLoading = true
    defer { isLoading = false }

    guard let currentAccountId,
      let myMembershipId = settingsProvider()?.membership?.membershipId
    else {
      displayName = fallbackDisplayName ?? String(localized: "User")
      handle = fallbackHandle ?? String(localized: "user")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let myMembershipIdBytes = myMembershipId.protobufBytes
    var pageToken = ""

    while true {
      let result = await messagingService.listContacts(
        accountId: currentAccountId,
        membershipId: myMembershipIdBytes,
        pageSize: 100,
        pageToken: pageToken,
        connectId: connectId
      )
      guard let response = result.ok() else { break }
      let match = response.contacts.first(where: { $0.membershipID == membershipId })
        ?? response.contacts.first(where: { $0.accountID == membershipId })
      if let match {
        resolvedMembershipId = match.membershipID
        displayName = match.displayName.isEmpty ? String(localized: "User") : match.displayName
        handle = match.handle.isEmpty ? String(localized: "user") : match.handle
        avatarUrl = match.hasAvatarURL ? match.avatarURL : nil
        isBlocked = match.relationship == .blocked
        return
      }
      if response.nextPageToken.isEmpty { break }
      pageToken = response.nextPageToken
    }
    displayName = fallbackDisplayName ?? String(localized: "User")
    handle = fallbackHandle ?? String(localized: "user")
    avatarUrl = nil
  }

  func createConversation() async -> Data? {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("Profile: missing accountId for createConversation")
      return nil
    }
    guard let myMembershipId = settingsProvider()?.membership?.membershipId else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      AppLogger.messaging.error("Profile: no membershipId for createConversation")
      return nil
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.createDirectConversation(
      accountId: currentAccountId,
      membershipId: myMembershipId.protobufBytes,
      recipientMembershipId: effectiveMembershipId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      return response.conversation.conversationID
    case .err(let error):
      AppLogger.messaging.error(
        "Profile: failed to create conversation: \(error, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
      return nil
    }
  }

  func toggleBlock() async {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("Profile: missing accountId for toggleBlock")
      return
    }
    guard let myMembershipId = settingsProvider()?.membership?.membershipId else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      AppLogger.messaging.error("Profile: no membershipId for toggleBlock")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    if isBlocked {
      let result = await messagingService.unblockContact(
        accountId: currentAccountId,
        membershipId: myMembershipId.protobufBytes,
        targetMembershipId: effectiveMembershipId,
        connectId: connectId
      )
      switch result {
      case .ok: isBlocked = false
      case .err(let error):
        hasError = true
        errorMessage = error.userFacingMessage
      }
    } else {
      let result = await messagingService.blockContact(
        accountId: currentAccountId,
        membershipId: myMembershipId.protobufBytes,
        targetMembershipId: effectiveMembershipId,
        connectId: connectId
      )
      switch result {
      case .ok: isBlocked = true
      case .err(let error):
        hasError = true
        errorMessage = error.userFacingMessage
      }
    }
  }

  func resetState() {
    displayName = ""
    handle = ""
    avatarUrl = nil
    isLoading = false
    isBlocked = false
    hasError = false
    errorMessage = ""
    resolvedMembershipId = nil
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }
}
