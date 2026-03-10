// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum RpcServiceType: String {
  case getServerPublicKeys = "GetServerPublicKeys"
  case registerAppDevice = "RegisterAppDevice"
  case establishSecrecyChannel = "EstablishSecrecyChannel"
  case restoreSecrecyChannel = "RestoreSecrecyChannel"
  case establishAuthenticatedSecureChannel = "EstablishAuthenticatedSecureChannel"
  case validateMobileNumber = "ValidateMobileNumber"
  case validateMobileForRecovery = "ValidateMobileForRecovery"
  case checkMobileNumberAvailability = "CheckMobileNumberAvailability"
  case initiateVerification = "InitiateVerification"
  case verifyOtp = "VerifyOtp"
  case registrationInit = "RegistrationInit"
  case registrationComplete = "RegistrationComplete"
  case recoveryInit = "RecoveryInit"
  case recoveryComplete = "RecoveryComplete"
  case signInInitRequest = "SignInInitRequest"
  case signInCompleteRequest = "SignInCompleteRequest"
  case terminateSession = "TerminateSession"
  case anonymousLogout = "AnonymousLogout"
  case profileLookup = "ProfileLookup"
  case profileNameAvailability = "ProfileNameAvailability"
  case profileUpsert = "ProfileUpsert"
  case pinRegisterInit = "PinRegisterInit"
  case pinRegisterComplete = "PinRegisterComplete"
  case pinVerifyInit = "PinVerifyInit"
  case pinVerifyFinalize = "PinVerifyFinalize"
  case pinDisable = "PinDisable"
  case listConversations = "ListConversations"
  case getConversation = "GetConversation"
  case createDirectConversation = "CreateDirectConversation"
  case createGroupConversation = "CreateGroupConversation"
  case updateConversation = "UpdateConversation"
  case deleteConversation = "DeleteConversation"
  case pinConversation = "PinConversation"
  case muteConversation = "MuteConversation"
  case archiveConversation = "ArchiveConversation"
  case listMessages = "ListMessages"
  case sendMessage = "SendMessage"
  case editMessage = "EditMessage"
  case deleteMessage = "DeleteMessage"
  case forwardMessage = "ForwardMessage"
  case reactToMessage = "ReactToMessage"
  case markRead = "MarkRead"
  case addGroupMembers = "AddGroupMembers"
  case removeGroupMember = "RemoveGroupMember"
  case updateMemberRole = "UpdateMemberRole"
  case leaveGroup = "LeaveGroup"
  case sendTypingIndicator = "SendTypingIndicator"
  case searchContacts = "SearchContacts"
  case listContacts = "ListContacts"
  case blockContact = "BlockContact"
  case unblockContact = "UnblockContact"
  case subscribePresence = "SubscribePresence"
  case subscribeNewMessages = "SubscribeNewMessages"
  case subscribeTypingIndicators = "SubscribeTypingIndicators"
  case subscribePresenceUpdates = "SubscribePresenceUpdates"
  case getFeed = "GetFeed"
  case createPost = "CreatePost"
  case deletePost = "DeletePost"
  case editPost = "EditPost"
  case likePost = "LikePost"
  case repost = "Repost"
  case bookmarkPost = "BookmarkPost"
  case getPostThread = "GetPostThread"
  case getUserPosts = "GetUserPosts"
  case followUser = "FollowUser"
  case subscribeFeedUpdates = "SubscribeFeedUpdates"
  case e2eUploadKeyPackages = "E2EUploadKeyPackages"
  case e2eFetchKeyPackage = "E2EFetchKeyPackage"
  case e2eUploadPrekeyBundle = "E2EUploadPrekeyBundle"
  case e2eFetchPrekeyBundle = "E2EFetchPrekeyBundle"
  case e2eSendGroupCommit = "E2ESendGroupCommit"
  case e2eSendGroupMessage = "E2ESendGroupMessage"
  case e2eSendWelcome = "E2ESendWelcome"
  case e2eFetchPendingEvents = "E2EFetchPendingEvents"
  case e2eAckEvents = "E2EAckEvents"
  case e2eDeviceLinkInit = "E2EDeviceLinkInit"
  case e2eDeviceLinkComplete = "E2EDeviceLinkComplete"
  case e2ePendingEventsStream = "E2EPendingEventsStream"
  case createChannel = "CreateChannel"
  case updateChannelSettings = "UpdateChannelSettings"
  case recordPostView = "RecordPostView"
  case linkDiscussionGroup = "LinkDiscussionGroup"
  case searchPublicChannels = "SearchPublicChannels"
  var description: String {
    rawValue
  }
}

struct RpcCallOptions {

  let timeout: TimeInterval
  let metadata: [String: String]

  init(timeout: TimeInterval = 30, metadata: [String: String] = [:]) {
    self.timeout = timeout
    self.metadata = metadata
  }

  static let `default` = RpcCallOptions()
}
