// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

protocol AppLifecycleProviding: AnyObject {

  var applicationInitializer: any ApplicationInitializing { get }
  var applicationStateManager: ApplicationStateManager { get }
  var appFlowResolver: AppFlowResolver { get }
  var settings: DefaultSystemSettings { get }

  func currentAppSettings() -> ApplicationInstanceSettings?

  func currentConnectId(exchangeType: PubKeyExchangeType) -> ConnectId

  func resolveStoredIdentity() -> (accountId: UUID, membershipId: UUID)?

  func activateAccountDatabase(accountId: UUID) -> Bool

  func deactivateAccountDatabase()

  func startRealtimeServices()

  func stopRealtimeServices() async
}

protocol AuthenticationFlowBuilding: AnyObject {

  @MainActor func makeSignInViewModel(
    onSignInInitiateSuccess: @escaping (String, String, SignInCreationStatus) -> Void,
    onAccountRecovery: @escaping () -> Void, onAutoRedirectComplete: @escaping () -> Void
  ) -> SignInViewModel
  @MainActor func makeOtpVerificationViewModel(
    sessionId: String, mobileNumber: String, flowContext: AuthenticationFlowContext,
    onVerificationSucceeded: @escaping (OtpVerificationResult) -> Void,
    onAutoRedirect: @escaping (OtpCountdownStatus) -> Void
  ) -> OtpVerificationViewModel
  @MainActor func makeMobileVerificationViewModel(
    flowContext: AuthenticationFlowContext,
    onMobileVerified: @escaping (MobileVerificationRoute) -> Void
  ) -> MobileVerificationViewModel
  @MainActor func makeSecureKeyConfirmationViewModel(
    flowContext: AuthenticationFlowContext, mobileNumber: String, membershipId: UUID?,
    membershipIdBytes: Data?, onSecureKeyConfirmed: @escaping () -> Void
  ) -> SecureKeyConfirmationViewModel
  @MainActor func makeCompleteProfileViewModel(
    sessionId: String, mobileNumber: String, onProfileCompleted: @escaping () -> Void
  ) -> CompleteProfileViewModel
  @MainActor func makePinSetupViewModel(onPinSetupCompleted: @escaping () -> Void)
    -> PinSetupViewModel
  @MainActor func makePinEntryViewModel(
    onPinVerified: @escaping () -> Void,
    onPinSetupRequired: @escaping () -> Void
  ) -> PinEntryViewModel
  @MainActor func makeWelcomeBackViewModel(
    onContinueToSetup: @escaping (UUID, String, Data?) -> Void,
    onContinueLater: @escaping () -> Void
  ) -> WelcomeBackViewModel
}

protocol SettingsFlowProviding: AnyObject {

  var logoutService: LogoutService { get }

  @MainActor func makeLogoutViewModel() -> LogoutViewModel
  @MainActor func makeAccountSettingsViewModel() -> AccountSettingsViewModel
  @MainActor func makeOutboxDiagnosticsViewModel() -> OutboxDiagnosticsViewModel
}

protocol MessagingFlowBuilding: AnyObject {

  @MainActor func makeConversationListViewModel() -> ConversationListViewModel
  @MainActor func makeChatDetailViewModel(conversationId: Data) -> ChatDetailViewModel
  @MainActor func makeConversationInfoViewModel(conversationId: Data) -> ConversationInfoViewModel
  @MainActor func makeNewConversationViewModel() -> NewConversationViewModel
  @MainActor func makeNewGroupViewModel() -> NewGroupViewModel
  @MainActor func makeGroupCreationViewModel(memberIds: [Data]) -> GroupCreationViewModel
  @MainActor func makeContactSearchViewModel() -> ContactSearchViewModel
  @MainActor func makeProfileViewModel(
    membershipId: Data, fallbackDisplayName: String?, fallbackHandle: String?
  ) -> ProfileViewModel
  @MainActor func makePhoneContactsViewModel(onContactSelected: @escaping (Data) -> Void)
    -> PhoneContactsViewModel
  @MainActor func makeChannelFeedViewModel(channelId: Data) -> ChannelFeedViewModel
  @MainActor func makeChannelInfoViewModel(channelId: Data) -> ChannelInfoViewModel
  @MainActor func makeCreateChannelViewModel() -> CreateChannelViewModel
}

protocol FeedFlowBuilding: AnyObject {

  @MainActor func makeFeedListViewModel() -> FeedListViewModel
  @MainActor func makePostDetailViewModel(postId: Data) -> PostDetailViewModel
  @MainActor func makeCreatePostViewModel(onPostCreated: @escaping () -> Void)
    -> CreatePostViewModel
  @MainActor func makeCreateReplyViewModel(
    parentPostId: Data, parentAuthorName: String, onPostCreated: @escaping () -> Void
  ) -> CreatePostViewModel
  @MainActor func makeCreateQuoteViewModel(quotedPostId: Data, onPostCreated: @escaping () -> Void)
    -> CreatePostViewModel
}

protocol AppCoordinatorDependencyProviding:
  AppLifecycleProviding,
  AuthenticationFlowBuilding,
  SettingsFlowProviding,
  MessagingFlowBuilding,
  FeedFlowBuilding
{}
