import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class UserProfileViewModel: Resettable {

  var displayName: String = ""
  var profileName: String = ""
  var avatarUrl: String?
  var isLoading: Bool = false
  var isBlocked: Bool = false

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let membershipId: Data

  init(
    membershipId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.membershipId = membershipId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadProfile() async {
    isLoading = true
    defer { isLoading = false }

    guard let currentAccountId,
      let myMembershipId = settingsProvider()?.membership?.membershipId
    else {
      displayName = String(localized: "User")
      profileName = String(localized: "user")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.listContacts(
      accountId: currentAccountId,
      membershipId: myMembershipId.protobufBytes,
      pageSize: 200,
      pageToken: "",
      connectId: connectId
    )
    if let contact = result.ok()?.contacts.first(where: { $0.membershipID == membershipId }) {
      displayName = contact.displayName.isEmpty ? String(localized: "User") : contact.displayName
      profileName = contact.profileName.isEmpty ? String(localized: "user") : contact.profileName
      avatarUrl = contact.hasAvatarURL ? contact.avatarURL : nil
      return
    }
    displayName = String(localized: "User")
    profileName = String(localized: "user")
    avatarUrl = nil
  }

  func createConversation() async -> Data? {
    guard let currentAccountId else {
      AppLogger.messaging.error("UserProfile: missing accountId for createConversation")
      return nil
    }
    guard let myMembershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("UserProfile: no membershipId for createConversation")
      return nil
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.createDirectConversation(
      accountId: currentAccountId,
      membershipId: myMembershipId.protobufBytes,
      recipientMembershipId: membershipId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      return response.conversation.conversationID
    case .err(let error):
      AppLogger.messaging.error(
        "UserProfile: failed to create conversation: \(error, privacy: .public)")
      return nil
    }
  }

  func toggleBlock() async {
    guard let currentAccountId else {
      AppLogger.messaging.error("UserProfile: missing accountId for toggleBlock")
      return
    }
    guard let myMembershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("UserProfile: no membershipId for toggleBlock")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    if isBlocked {
      let result = await messagingService.unblockContact(
        accountId: currentAccountId,
        membershipId: myMembershipId.protobufBytes,
        targetMembershipId: membershipId,
        connectId: connectId
      )
      if case .ok = result { isBlocked = false }
    } else {
      let result = await messagingService.blockContact(
        accountId: currentAccountId,
        membershipId: myMembershipId.protobufBytes,
        targetMembershipId: membershipId,
        connectId: connectId
      )
      if case .ok = result { isBlocked = true }
    }
  }

  func resetState() {
    displayName = ""
    profileName = ""
    avatarUrl = nil
    isLoading = false
    isBlocked = false
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }
}
