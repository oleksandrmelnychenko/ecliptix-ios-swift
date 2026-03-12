// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

@Observable @MainActor
final class ChannelInfoViewModel: Resettable {

  var channelTitle: String = ""
  var channelDescription: String = ""
  var avatarUrl: String?
  var subscriberCount: Int32 = 0
  var adminSignatures: Bool = false
  var isPublic: Bool?
  var slowModeSeconds: Int32?
  var admins: [MemberDisplayItem] = []
  var isAdmin: Bool = false
  var isOwner: Bool = false
  var isLoading: Bool = false
  var isSaving: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""

  let channelId: Data
  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> ConnectId

  init(
    channelId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> ConnectId
  ) {
    self.channelId = channelId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadInfo() async {
    isLoading = true
    defer { isLoading = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.getConversation(
      conversationId: channelId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let conv = response.conversation
      channelTitle = conv.title
      channelDescription = conv.description_p
      avatarUrl = conv.hasAvatarURL ? conv.avatarURL : nil
      subscriberCount = conv.subscriberCount
      adminSignatures = conv.adminSignatures
      isPublic = conv.hasIsPublic ? conv.isPublic : nil
      slowModeSeconds = conv.hasSlowModeSeconds ? conv.slowModeSeconds : nil

      let membershipBytes = settingsProvider()?.membership?.membershipId.protobufBytes
      var adminList: [MemberDisplayItem] = []
      for member in conv.members {
        let role = member.role
        if role == .owner || role == .admin {
          adminList.append(
            MemberDisplayItem(
              id: member.membershipID,
              accountId: member.accountID,
              displayName: member.displayName,
              handle: member.handle,
              avatarUrl: member.hasAvatarURL ? member.avatarURL : nil,
              role: role == .owner ? .owner : .admin,
              joinedAt: member.hasJoinedAt ? member.joinedAt.date : nil
            )
          )
        }
        if let membershipBytes, member.membershipID == membershipBytes {
          isAdmin = role == .owner || role == .admin
          isOwner = role == .owner
        }
      }
      admins = adminList
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelInfo: loadInfo failed: \(error.logDescription, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
    }
  }

  func updateSettings() async {
    isSaving = true
    defer { isSaving = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.updateChannelSettings(
      channelId: channelId,
      title: channelTitle,
      description: channelDescription,
      isPublic: isPublic,
      adminSignatures: adminSignatures,
      slowModeSeconds: slowModeSeconds,
      connectId: connectId
    )
    switch result {
    case .ok:
      hasError = false
    case .err(let error):
      AppLogger.messaging.error(
        "ChannelInfo: updateSettings failed: \(error.logDescription, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
    }
  }

  func resetState() {
    channelTitle = ""
    channelDescription = ""
    avatarUrl = nil
    subscriberCount = 0
    adminSignatures = false
    isPublic = nil
    slowModeSeconds = nil
    admins = []
    isAdmin = false
    isOwner = false
    isLoading = false
    isSaving = false
    hasError = false
    errorMessage = ""
  }
}
