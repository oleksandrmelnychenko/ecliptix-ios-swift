import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftProtobuf
import os

@Observable @MainActor
final class ConversationInfoViewModel: Resettable {

  var conversationTitle: String = ""
  var conversationDescription: String = ""
  var avatarUrl: String?
  var members: [MemberDisplayItem] = []
  var isGroup: Bool = false
  var isAdmin: Bool = false
  var isOwner: Bool = false
  var isLoading: Bool = false
  var isSaving: Bool = false
  var muteStatus: ProtoMuteStatus = .unmuted
  var hasError: Bool = false
  var errorMessage: String = ""
  var didLeaveGroup: Bool = false

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  let conversationId: Data

  init(
    conversationId: Data,
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.conversationId = conversationId
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func loadInfo() async {
    isLoading = true
    defer { isLoading = false }

    hasError = false
    errorMessage = ""
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let membershipId = resolveMembershipIdBytes()
    let result = await messagingService.getConversation(
      conversationId: conversationId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      let conv = response.conversation
      conversationTitle = conv.title
      conversationDescription = conv.description_p
      isGroup = conv.type == .group
      muteStatus = conv.muteStatus
      members = conv.members.map { member in
        MemberDisplayItem(
          id: member.membershipID,
          accountId: member.accountID,
          displayName: member.displayName,
          profileName: member.profileName,
          avatarUrl: member.hasAvatarURL ? member.avatarURL : nil,
          role: MemberDisplayItem.MemberRole(rawValue: member.role.rawValue) ?? .member,
          joinedAt: member.hasJoinedAt ? member.joinedAt.date : nil
        )
      }
      if let membershipId,
        let me = members.first(where: { $0.id == membershipId })
      {
        isAdmin = me.role == .admin || me.role == .owner
        isOwner = me.role == .owner
      } else {
        isAdmin = false
        isOwner = false
      }
    case .err(let rpcError):
      AppLogger.messaging.error(
        "ConversationInfo: failed to load conversation: \(rpcError.logDescription, privacy: .public)"
      )
      #if DEBUG
        loadMockData()
      #else
        members = []
        hasError = true
        errorMessage = rpcError.userFacingMessage
      #endif
    }
  }

  func updateGroupTitle(_ title: String) async {
    isSaving = true
    defer { isSaving = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.updateConversation(
      conversationId: conversationId,
      title: title,
      description: nil,
      connectId: connectId
    )
    if case .ok = result {
      conversationTitle = title
    }
  }

  func addMembers(_ ids: [Data]) async {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("ConversationInfo: missing accountId for addMembers")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    guard let membershipId = resolveMembershipIdBytes() else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return
    }

    let result = await messagingService.addGroupMembers(
      accountId: currentAccountId,
      membershipId: membershipId,
      conversationId: conversationId,
      newMemberIds: ids,
      connectId: connectId
    )
    if case .ok(let response) = result {
      let newMembers = response.addedMembers.map { member in
        MemberDisplayItem(
          id: member.membershipID,
          accountId: member.accountID,
          displayName: "",
          profileName: "",
          avatarUrl: nil,
          role: MemberDisplayItem.MemberRole(rawValue: member.role.rawValue) ?? .member,
          joinedAt: member.hasJoinedAt ? member.joinedAt.date : nil
        )
      }
      members.append(contentsOf: newMembers)
    }
  }

  func removeMember(_ id: Data) async {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("ConversationInfo: missing accountId for removeMember")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    guard let membershipId = resolveMembershipIdBytes() else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return
    }

    let result = await messagingService.removeGroupMember(
      accountId: currentAccountId,
      membershipId: membershipId,
      conversationId: conversationId,
      targetMembershipId: id,
      connectId: connectId
    )
    if case .ok = result {
      members.removeAll { $0.id == id }
    }
  }

  func updateMemberRole(_ id: Data, role: MemberDisplayItem.MemberRole) async {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("ConversationInfo: missing accountId for updateMemberRole")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    guard let membershipId = resolveMembershipIdBytes() else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return
    }

    let protoRole = ProtoParticipantRole(rawValue: role.rawValue) ?? .member
    let result = await messagingService.updateMemberRole(
      accountId: currentAccountId,
      membershipId: membershipId,
      conversationId: conversationId,
      targetMembershipId: id,
      newRole: protoRole,
      connectId: connectId
    )
    if case .ok = result {
      if let index = members.firstIndex(where: { $0.id == id }) {
        members[index].role = role
      }
    }
  }

  func leaveGroup() async {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("ConversationInfo: missing accountId for leaveGroup")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    guard let membershipId = resolveMembershipIdBytes() else {
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return
    }

    let leaveResult = await messagingService.leaveGroup(
      accountId: currentAccountId,
      membershipId: membershipId,
      conversationId: conversationId,
      connectId: connectId
    )
    if let error = leaveResult.err() {
      AppLogger.messaging.warning("Failed to leave group: \(error, privacy: .public)")
      hasError = true
      errorMessage = error.userFacingMessage
      return
    }
    didLeaveGroup = true
  }

  func muteConversation(_ status: ProtoMuteStatus) async {
    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.muteConversation(
      conversationId: conversationId,
      muteStatus: status,
      connectId: connectId
    )
    if case .ok = result {
      muteStatus = status
    }
  }

  func resetState() {
    conversationTitle = ""
    conversationDescription = ""
    members = []
    isLoading = false
    isSaving = false
    hasError = false
    errorMessage = ""
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  private func resolveMembershipIdBytes() -> Data? {
    guard let settings = settingsProvider(),
      let membershipId = settings.membership?.membershipId
    else {
      return nil
    }
    return membershipId.protobufBytes
  }

  private func loadMockData() {
    conversationTitle = "Ecliptix Team"
    conversationDescription = "Development team chat"
    isGroup = true
    isAdmin = true
    members = [
      MemberDisplayItem(
        id: Data([1]), accountId: Data([1]), displayName: "You", profileName: "me", avatarUrl: nil,
        role: .owner, joinedAt: Date().addingTimeInterval(-86400 * 30)),
      MemberDisplayItem(
        id: Data([2]), accountId: Data([2]), displayName: "Alice Johnson", profileName: "alice",
        avatarUrl: nil, role: .admin, joinedAt: Date().addingTimeInterval(-86400 * 25)),
      MemberDisplayItem(
        id: Data([3]), accountId: Data([3]), displayName: "Bob Smith", profileName: "bob",
        avatarUrl: nil, role: .member, joinedAt: Date().addingTimeInterval(-86400 * 20)),
      MemberDisplayItem(
        id: Data([4]), accountId: Data([4]), displayName: "Carol Williams", profileName: "carol",
        avatarUrl: nil, role: .member, joinedAt: Date().addingTimeInterval(-86400 * 10)),
    ]
  }
}
