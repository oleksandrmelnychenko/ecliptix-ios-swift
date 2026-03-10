import CryptoKit
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class MessagingRpcService {

  private let pipeline: SecureUnaryPipeline

  init(
    transport: EventGatewayTransport,
    secureSessionClient: any SecureSessionClient & NetworkOutageControlling,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService
  ) {
    self.pipeline = SecureUnaryPipeline(
      transport: transport,
      secureSessionClient: secureSessionClient,
      log: AppLogger.messaging,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
  }

  func listConversations(
    limit: UInt32 = 50,
    cursor: Data? = nil,
    connectId: UInt32
  ) async -> Result<ProtoListConversationsResponse, RpcError> {
    var request = ProtoListConversationsRequest()
    request.limit = limit
    if let cursor {
      request.cursor = cursor
    }
    AppLogger.messaging.info(
      "ListConversations: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .listConversations,
      request: request,
      connectId: connectId,
      label: "ListConversations"
    )
  }

  func getConversation(
    conversationId: Data,
    connectId: UInt32
  ) async -> Result<ProtoGetConversationResponse, RpcError> {
    var request = ProtoGetConversationRequest()
    request.conversationID = conversationId
    AppLogger.messaging.info(
      "GetConversation: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .getConversation,
      request: request,
      connectId: connectId,
      label: "GetConversation"
    )
  }

  func createDirectConversation(
    accountId: Data,
    membershipId: Data,
    recipientMembershipId: Data,
    connectId: UInt32
  ) async -> Result<ProtoCreateDirectConversationResponse, RpcError> {
    var request = ProtoCreateDirectConversationRequest()
    request.accountID = accountId
    request.initiatorMembershipID = membershipId
    request.recipientMembershipID = recipientMembershipId
    AppLogger.messaging.info(
      "CreateDirectConversation: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .createDirectConversation,
      request: request,
      connectId: connectId,
      label: "CreateDirectConversation"
    )
  }

  func createGroupConversation(
    accountId: Data,
    membershipId: Data,
    title: String,
    description: String?,
    memberIds: [Data],
    shieldMode: Bool,
    connectId: UInt32
  ) async -> Result<ProtoCreateGroupConversationResponse, RpcError> {
    var request = ProtoCreateGroupConversationRequest()
    request.accountID = accountId
    request.creatorMembershipID = membershipId
    request.title = title
    if let description {
      request.description_p = description
    }
    request.memberMembershipIds = memberIds
    request.shieldMode = shieldMode
    AppLogger.messaging.info(
      "CreateGroupConversation: start connectId=\(connectId, privacy: .public), memberCount=\(memberIds.count, privacy: .public), shieldMode=\(shieldMode, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .createGroupConversation,
      request: request,
      connectId: connectId,
      label: "CreateGroupConversation"
    )
  }

  func updateConversation(
    conversationId: Data,
    title: String?,
    description: String?,
    connectId: UInt32
  ) async -> Result<ProtoUpdateConversationResponse, RpcError> {
    var request = ProtoUpdateConversationRequest()
    request.conversationID = conversationId
    if let title {
      request.title = title
    }
    if let description {
      request.description_p = description
    }
    AppLogger.messaging.info(
      "UpdateConversation: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .updateConversation,
      request: request,
      connectId: connectId,
      label: "UpdateConversation"
    )
  }

  func deleteConversation(
    conversationId: Data,
    connectId: UInt32
  ) async -> Result<ProtoDeleteConversationResponse, RpcError> {
    var request = ProtoDeleteConversationRequest()
    request.conversationID = conversationId
    AppLogger.messaging.info(
      "DeleteConversation: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .deleteConversation,
      request: request,
      connectId: connectId,
      label: "DeleteConversation"
    )
  }

  func pinConversation(
    conversationId: Data,
    isPinned: Bool,
    connectId: UInt32
  ) async -> Result<ProtoPinConversationResponse, RpcError> {
    var request = ProtoPinConversationRequest()
    request.conversationID = conversationId
    request.isPinned = isPinned
    AppLogger.messaging.info(
      "PinConversation: start connectId=\(connectId, privacy: .public), isPinned=\(isPinned, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .pinConversation,
      request: request,
      connectId: connectId,
      label: "PinConversation"
    )
  }

  func muteConversation(
    conversationId: Data,
    muteStatus: ProtoMuteStatus,
    connectId: UInt32
  ) async -> Result<ProtoMuteConversationResponse, RpcError> {
    var request = ProtoMuteConversationRequest()
    request.conversationID = conversationId
    request.muteStatus = muteStatus
    AppLogger.messaging.info(
      "MuteConversation: start connectId=\(connectId, privacy: .public), muteStatus=\(muteStatus.rawValue, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .muteConversation,
      request: request,
      connectId: connectId,
      label: "MuteConversation"
    )
  }

  func archiveConversation(
    conversationId: Data,
    archive: Bool,
    connectId: UInt32
  ) async -> Result<ProtoArchiveConversationResponse, RpcError> {
    var request = ProtoArchiveConversationRequest()
    request.conversationID = conversationId
    request.archive = archive
    AppLogger.messaging.info(
      "ArchiveConversation: start connectId=\(connectId, privacy: .public), archive=\(archive, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .archiveConversation,
      request: request,
      connectId: connectId,
      label: "ArchiveConversation"
    )
  }

  func listMessages(
    conversationId: Data,
    pageSize: Int32,
    beforeMessageId: Data? = nil,
    afterMessageId: Data? = nil,
    connectId: UInt32
  ) async -> Result<ProtoListMessagesResponse, RpcError> {
    var request = ProtoListMessagesRequest()
    request.conversationID = conversationId
    if pageSize > 0 {
      request.pageSize = pageSize
    }
    if let beforeMessageId {
      request.beforeMessageID = beforeMessageId
    }
    if let afterMessageId {
      request.afterMessageID = afterMessageId
    }
    AppLogger.messaging.info(
      "ListMessages: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public), pageSize=\(pageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .listMessages,
      request: request,
      connectId: connectId,
      label: "ListMessages"
    )
  }

  func sendMessage(
    conversationId: Data,
    textContent: String,
    replyToMessageId: Data?,
    clientMessageId: String,
    connectId: UInt32
  ) async -> Result<ProtoSendMessageResponse, RpcError> {
    var request = ProtoSendMessageRequest()
    request.conversationID = conversationId
    var text = ProtoTextContent()
    text.body = textContent
    request.content = .init()
    request.content.text = text
    if let replyToMessageId {
      request.replyToMessageID = replyToMessageId
    }
    request.clientMessageID = clientMessageId
    AppLogger.messaging.info(
      "SendMessage: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public), clientMessageId=\(clientMessageId, privacy: .private(mask: .hash))"
    )
    return await executeTypedUnary(
      serviceType: .sendMessage,
      request: request,
      connectId: connectId,
      label: "SendMessage"
    )
  }

  func editMessage(
    messageId: Data,
    conversationId: Data,
    textContent: String,
    connectId: UInt32
  ) async -> Result<ProtoEditMessageResponse, RpcError> {
    var request = ProtoEditMessageRequest()
    request.messageID = messageId
    request.conversationID = conversationId
    var text = ProtoTextContent()
    text.body = textContent
    request.newContent = .init()
    request.newContent.text = text
    AppLogger.messaging.info(
      "EditMessage: start connectId=\(connectId, privacy: .public), messageIdBytes=\(messageId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .editMessage,
      request: request,
      connectId: connectId,
      label: "EditMessage"
    )
  }

  func deleteMessage(
    messageId: Data,
    conversationId: Data,
    deleteForEveryone: Bool,
    connectId: UInt32
  ) async -> Result<ProtoDeleteMessageResponse, RpcError> {
    var request = ProtoDeleteMessageRequest()
    request.messageID = messageId
    request.conversationID = conversationId
    request.deleteForEveryone = deleteForEveryone
    AppLogger.messaging.info(
      "DeleteMessage: start connectId=\(connectId, privacy: .public), messageIdBytes=\(messageId.count, privacy: .public), deleteForEveryone=\(deleteForEveryone, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .deleteMessage,
      request: request,
      connectId: connectId,
      label: "DeleteMessage"
    )
  }

  func forwardMessage(
    messageId: Data,
    targetConversationId: Data,
    connectId: UInt32
  ) async -> Result<ProtoForwardMessageResponse, RpcError> {
    var request = ProtoForwardMessageRequest()
    request.messageID = messageId
    request.targetConversationID = targetConversationId
    AppLogger.messaging.info(
      "ForwardMessage: start connectId=\(connectId, privacy: .public), messageIdBytes=\(messageId.count, privacy: .public), targetConversationIdBytes=\(targetConversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .forwardMessage,
      request: request,
      connectId: connectId,
      label: "ForwardMessage"
    )
  }

  func reactToMessage(
    messageId: Data,
    conversationId: Data,
    emoji: String,
    remove: Bool = false,
    connectId: UInt32
  ) async -> Result<ProtoReactionResponse, RpcError> {
    var request = ProtoReactionRequest()
    request.messageID = messageId
    request.conversationID = conversationId
    request.emoji = emoji
    request.remove = remove
    AppLogger.messaging.info(
      "ReactToMessage: start connectId=\(connectId, privacy: .public), messageIdBytes=\(messageId.count, privacy: .public), remove=\(remove, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .reactToMessage,
      request: request,
      connectId: connectId,
      label: "ReactToMessage"
    )
  }

  func markRead(
    conversationId: Data,
    upToMessageId: Data,
    connectId: UInt32
  ) async -> Result<ProtoMarkReadResponse, RpcError> {
    var request = ProtoMarkReadRequest()
    request.conversationID = conversationId
    request.upToMessageID = upToMessageId
    AppLogger.messaging.info(
      "MarkRead: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .markRead,
      request: request,
      connectId: connectId,
      label: "MarkRead"
    )
  }

  func addGroupMembers(
    accountId: Data,
    membershipId: Data,
    conversationId: Data,
    newMemberIds: [Data],
    connectId: UInt32
  ) async -> Result<ProtoAddGroupMembersResponse, RpcError> {
    var request = ProtoAddGroupMembersRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.conversationID = conversationId
    request.newMemberMembershipIds = newMemberIds
    AppLogger.messaging.info(
      "AddGroupMembers: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public), newMemberCount=\(newMemberIds.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .addGroupMembers,
      request: request,
      connectId: connectId,
      label: "AddGroupMembers"
    )
  }

  func removeGroupMember(
    accountId: Data,
    membershipId: Data,
    conversationId: Data,
    targetMembershipId: Data,
    connectId: UInt32
  ) async -> Result<ProtoRemoveGroupMemberResponse, RpcError> {
    var request = ProtoRemoveGroupMemberRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.conversationID = conversationId
    request.targetMembershipID = targetMembershipId
    AppLogger.messaging.info(
      "RemoveGroupMember: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .removeGroupMember,
      request: request,
      connectId: connectId,
      label: "RemoveGroupMember"
    )
  }

  func updateMemberRole(
    accountId: Data,
    membershipId: Data,
    conversationId: Data,
    targetMembershipId: Data,
    newRole: ProtoParticipantRole,
    connectId: UInt32
  ) async -> Result<ProtoUpdateMemberRoleResponse, RpcError> {
    var request = ProtoUpdateMemberRoleRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.conversationID = conversationId
    request.targetMembershipID = targetMembershipId
    request.newRole = newRole
    AppLogger.messaging.info(
      "UpdateMemberRole: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public), newRole=\(newRole.rawValue, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .updateMemberRole,
      request: request,
      connectId: connectId,
      label: "UpdateMemberRole"
    )
  }

  func leaveGroup(
    accountId: Data,
    membershipId: Data,
    conversationId: Data,
    connectId: UInt32
  ) async -> Result<ProtoLeaveGroupResponse, RpcError> {
    var request = ProtoLeaveGroupRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.conversationID = conversationId
    AppLogger.messaging.info(
      "LeaveGroup: start connectId=\(connectId, privacy: .public), conversationIdBytes=\(conversationId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .leaveGroup,
      request: request,
      connectId: connectId,
      label: "LeaveGroup"
    )
  }

  func searchContacts(
    accountId: Data,
    membershipId: Data,
    query: String,
    pageSize: Int32,
    connectId: UInt32
  ) async -> Result<ProtoSearchContactsResponse, RpcError> {
    var request = ProtoSearchContactsRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.query = query
    if pageSize > 0 {
      request.pageSize = pageSize
    }
    AppLogger.messaging.info(
      "SearchContacts: start connectId=\(connectId, privacy: .public), queryLength=\(query.count, privacy: .public), pageSize=\(pageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .searchContacts,
      request: request,
      connectId: connectId,
      label: "SearchContacts"
    )
  }

  func listContacts(
    accountId: Data,
    membershipId: Data,
    pageSize: Int32,
    pageToken: String,
    connectId: UInt32
  ) async -> Result<ProtoListContactsResponse, RpcError> {
    var request = ProtoListContactsRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    if pageSize > 0 {
      request.pageSize = pageSize
    }
    if !pageToken.isEmpty {
      request.pageToken = pageToken
    }
    AppLogger.messaging.info(
      "ListContacts: start connectId=\(connectId, privacy: .public), pageSize=\(pageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .listContacts,
      request: request,
      connectId: connectId,
      label: "ListContacts"
    )
  }

  func blockContact(
    accountId: Data,
    membershipId: Data,
    targetMembershipId: Data,
    connectId: UInt32
  ) async -> Result<ProtoBlockContactResponse, RpcError> {
    var request = ProtoBlockContactRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.targetMembershipID = targetMembershipId
    AppLogger.messaging.info(
      "BlockContact: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .blockContact,
      request: request,
      connectId: connectId,
      label: "BlockContact"
    )
  }

  func unblockContact(
    accountId: Data,
    membershipId: Data,
    targetMembershipId: Data,
    connectId: UInt32
  ) async -> Result<ProtoUnblockContactResponse, RpcError> {
    var request = ProtoUnblockContactRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.targetMembershipID = targetMembershipId
    AppLogger.messaging.info(
      "UnblockContact: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .unblockContact,
      request: request,
      connectId: connectId,
      label: "UnblockContact"
    )
  }

  func sendTypingIndicator(
    conversationId: Data,
    isTyping: Bool,
    connectId: UInt32
  ) async -> Result<ProtoTypingIndicatorResponse, RpcError> {
    var request = ProtoTypingIndicatorRequest()
    request.conversationID = conversationId
    request.isTyping = isTyping
    AppLogger.messaging.info(
      "SendTypingIndicator: start connectId=\(connectId, privacy: .public), isTyping=\(isTyping, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .sendTypingIndicator,
      request: request,
      connectId: connectId,
      label: "SendTypingIndicator"
    )
  }

  // MARK: - Channels

  func createChannel(
    accountId: Data,
    membershipId: Data,
    title: String,
    description: String?,
    isPublic: Bool,
    adminSignatures: Bool,
    connectId: UInt32
  ) async -> Result<ProtoCreateChannelResponse, RpcError> {
    var request = ProtoCreateChannelRequest()
    request.accountID = accountId
    request.creatorMembershipID = membershipId
    request.title = title
    if let description {
      request.description_p = description
    }
    request.isPublic = isPublic
    request.adminSignatures = adminSignatures
    AppLogger.messaging.info(
      "CreateChannel: start connectId=\(connectId, privacy: .public), title=\(title, privacy: .private(mask: .hash))"
    )
    return await executeTypedUnary(
      serviceType: .createChannel,
      request: request,
      connectId: connectId,
      label: "CreateChannel"
    )
  }

  func updateChannelSettings(
    channelId: Data,
    title: String?,
    description: String?,
    isPublic: Bool?,
    adminSignatures: Bool?,
    slowModeSeconds: Int32?,
    connectId: UInt32
  ) async -> Result<ProtoUpdateChannelSettingsResponse, RpcError> {
    var request = ProtoUpdateChannelSettingsRequest()
    request.channelID = channelId
    if let title { request.title = title }
    if let description { request.description_p = description }
    if let isPublic { request.isPublic = isPublic }
    if let adminSignatures { request.adminSignatures = adminSignatures }
    if let slowModeSeconds { request.slowModeSeconds = slowModeSeconds }
    AppLogger.messaging.info(
      "UpdateChannelSettings: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .updateChannelSettings,
      request: request,
      connectId: connectId,
      label: "UpdateChannelSettings"
    )
  }

  func recordPostView(
    channelId: Data,
    messageIds: [Data],
    connectId: UInt32
  ) async -> Result<ProtoRecordPostViewResponse, RpcError> {
    var request = ProtoRecordPostViewRequest()
    request.channelID = channelId
    request.messageIds = messageIds
    return await executeTypedUnary(
      serviceType: .recordPostView,
      request: request,
      connectId: connectId,
      label: "RecordPostView"
    )
  }

  func linkDiscussionGroup(
    channelId: Data,
    groupId: Data,
    connectId: UInt32
  ) async -> Result<ProtoLinkDiscussionGroupResponse, RpcError> {
    var request = ProtoLinkDiscussionGroupRequest()
    request.channelID = channelId
    request.groupID = groupId
    AppLogger.messaging.info(
      "LinkDiscussionGroup: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .linkDiscussionGroup,
      request: request,
      connectId: connectId,
      label: "LinkDiscussionGroup"
    )
  }

  func searchPublicChannels(
    query: String,
    pageSize: Int32?,
    pageToken: String?,
    connectId: UInt32
  ) async -> Result<ProtoSearchPublicChannelsResponse, RpcError> {
    var request = ProtoSearchPublicChannelsRequest()
    request.query = query
    if let pageSize { request.pageSize = pageSize }
    if let pageToken { request.pageToken = pageToken }
    AppLogger.messaging.info(
      "SearchPublicChannels: start connectId=\(connectId, privacy: .public), query=\(query, privacy: .private(mask: .hash))"
    )
    return await executeTypedUnary(
      serviceType: .searchPublicChannels,
      request: request,
      connectId: connectId,
      label: "SearchPublicChannels"
    )
  }

  private func executeTypedUnary<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    serviceType: RpcServiceType,
    request: Request,
    connectId: UInt32,
    label: String
  ) async -> Result<Response, RpcError> {
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      AppLogger.messaging.error(
        "\(label): serialize failed connectId=\(connectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.serializationFailed("\(label) request"))
    }

    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: serviceType,
      plaintext: requestData,
      connectId: connectId
    )
    guard let decryptedPayload = decryptedResult.ok() else {
      AppLogger.messaging.warning(
        "\(label): secure unary failed connectId=\(connectId, privacy: .public), error=\(decryptedResult.unwrapErr().logDescription, privacy: .public)"
      )
      return decryptedResult.propagateErr()
    }

    let response: Response
    do {
      response = try Response(serializedBytes: decryptedPayload)
    } catch {
      AppLogger.messaging.error(
        "\(label): parse failed connectId=\(connectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.deserializationFailed("\(label) response: \(error.localizedDescription)"))
    }
    AppLogger.messaging.info(
      "\(label): success connectId=\(connectId, privacy: .public)"
    )
    return .ok(response)
  }
}
