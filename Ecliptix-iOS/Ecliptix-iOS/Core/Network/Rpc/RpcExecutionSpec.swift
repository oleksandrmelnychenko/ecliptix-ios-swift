// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum RpcInteractionModel: String, Sendable {
  case unary
  case serverStream
}

enum RpcDurability: String, Sendable {
  case query
  case ephemeralMutation
  case durableMutation
}

struct RpcRetryPolicy: Sendable {

  let maxAttempts: Int
  let initialDelay: TimeInterval
  let maxDelay: TimeInterval

  static let standard = RpcRetryPolicy(
    maxAttempts: max(1, AppConstants.Network.maxRetryAttempts),
    initialDelay: 0.5,
    maxDelay: 2.0
  )

  static let ephemeral = RpcRetryPolicy(
    maxAttempts: max(1, min(2, AppConstants.Network.maxRetryAttempts)),
    initialDelay: 0.15,
    maxDelay: 0.5
  )
}

struct RpcExecutionSpec: Sendable {

  let interactionModel: RpcInteractionModel
  let durability: RpcDurability
  let queueIfUnavailable: Bool
  let requiresIdempotency: Bool
  let retryPolicy: RpcRetryPolicy

  static let queryUnary = RpcExecutionSpec(
    interactionModel: .unary,
    durability: .query,
    queueIfUnavailable: false,
    requiresIdempotency: false,
    retryPolicy: .standard
  )

  static let ephemeralMutationUnary = RpcExecutionSpec(
    interactionModel: .unary,
    durability: .ephemeralMutation,
    queueIfUnavailable: false,
    requiresIdempotency: false,
    retryPolicy: .ephemeral
  )

  static func durableMutationUnary(
    queueIfUnavailable: Bool,
    requiresIdempotency: Bool
  ) -> RpcExecutionSpec {
    RpcExecutionSpec(
      interactionModel: .unary,
      durability: .durableMutation,
      queueIfUnavailable: queueIfUnavailable,
      requiresIdempotency: requiresIdempotency,
      retryPolicy: .standard
    )
  }

  static let serverStream = RpcExecutionSpec(
    interactionModel: .serverStream,
    durability: .query,
    queueIfUnavailable: false,
    requiresIdempotency: false,
    retryPolicy: .standard
  )

  var logDescription: String {
    "model=\(interactionModel.rawValue), durability=\(durability.rawValue), queueIfUnavailable=\(queueIfUnavailable), requiresIdempotency=\(requiresIdempotency), maxAttempts=\(retryPolicy.maxAttempts)"
  }
}

extension RpcServiceType {

  var executionSpec: RpcExecutionSpec {
    switch self {
    case .getServerPublicKeys,
      .validateMobileNumber,
      .validateMobileForRecovery,
      .checkMobileNumberAvailability,
      .profileLookup,
      .handleAvailability,
      .listConversations,
      .getConversation,
      .listMessages,
      .searchContacts,
      .listContacts,
      .getFeed,
      .getPostThread,
      .getUserPosts,
      .e2eFetchKeyPackage,
      .e2eFetchPrekeyBundle,
      .e2eFetchPendingEvents,
      .searchPublicChannels:
      return .queryUnary

    case .markRead,
      .sendTypingIndicator,
      .recordPostView,
      .e2eAckEvents:
      return .ephemeralMutationUnary

    case .subscribePresence,
      .initiateVerification,
      .subscribeNewMessages,
      .subscribeTypingIndicators,
      .subscribePresenceUpdates,
      .subscribeFeedUpdates,
      .e2ePendingEventsStream:
      return .serverStream

    case .sendMessage:
      return .durableMutationUnary(queueIfUnavailable: false, requiresIdempotency: true)

    case .editMessage,
      .deleteMessage,
      .reactToMessage:
      return .durableMutationUnary(queueIfUnavailable: true, requiresIdempotency: false)

    case .registerAppDevice,
      .establishSecrecyChannel,
      .restoreSecrecyChannel,
      .establishAuthenticatedSecureChannel,
      .verifyOtp,
      .registrationInit,
      .registrationComplete,
      .recoveryInit,
      .recoveryComplete,
      .signInInitRequest,
      .signInCompleteRequest,
      .terminateSession,
      .anonymousLogout,
      .profileUpsert,
      .pinRegisterInit,
      .pinRegisterComplete,
      .pinVerifyInit,
      .pinVerifyFinalize,
      .pinDisable,
      .createDirectConversation,
      .createGroupConversation,
      .forwardMessage,
      .updateConversation,
      .deleteConversation,
      .pinConversation,
      .muteConversation,
      .archiveConversation,
      .addGroupMembers,
      .removeGroupMember,
      .updateMemberRole,
      .leaveGroup,
      .blockContact,
      .unblockContact,
      .createPost,
      .deletePost,
      .editPost,
      .likePost,
      .repost,
      .bookmarkPost,
      .followUser,
      .createChannel,
      .updateChannelSettings,
      .linkDiscussionGroup,
      .e2eUploadKeyPackages,
      .e2eUploadPrekeyBundle,
      .e2eSendGroupCommit,
      .e2eSendGroupMessage,
      .e2eSendWelcome,
      .e2eDeviceLinkInit,
      .e2eDeviceLinkComplete:
      return .durableMutationUnary(queueIfUnavailable: false, requiresIdempotency: false)
    }
  }

  var supportsSyntheticQueuedSuccess: Bool {
    switch self {
    case .sendMessage,
      .editMessage,
      .deleteMessage,
      .reactToMessage:
      return true
    default:
      return false
    }
  }
}
