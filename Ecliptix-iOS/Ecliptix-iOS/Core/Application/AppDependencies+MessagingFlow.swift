// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension AppDependencies {

  @MainActor
  func makeConversationListViewModel() -> ConversationListViewModel {
    ConversationListViewModel(
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeChatDetailViewModel(conversationId: Data) -> ChatDetailViewModel {
    ChatDetailViewModel(
      conversationId: conversationId,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeConversationInfoViewModel(conversationId: Data) -> ConversationInfoViewModel {
    ConversationInfoViewModel(
      conversationId: conversationId,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeNewConversationViewModel() -> NewConversationViewModel {
    NewConversationViewModel(
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeNewGroupViewModel() -> NewGroupViewModel {
    NewGroupViewModel(
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeGroupCreationViewModel(memberIds: [Data]) -> GroupCreationViewModel {
    GroupCreationViewModel(
      memberIds: memberIds,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeContactSearchViewModel() -> ContactSearchViewModel {
    ContactSearchViewModel(
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeUserProfileViewModel(membershipId: Data) -> UserProfileViewModel {
    UserProfileViewModel(
      membershipId: membershipId,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makePhoneContactsViewModel(
    onContactSelected: @escaping (Data) -> Void = { _ in }
  ) -> PhoneContactsViewModel {
    PhoneContactsViewModel(
      contactsService: phoneContactsService,
      profileService: profileRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider(),
      onContactSelected: onContactSelected
    )
  }

  @MainActor
  func makeChannelFeedViewModel(channelId: Data) -> ChannelFeedViewModel {
    ChannelFeedViewModel(
      channelId: channelId,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeChannelInfoViewModel(channelId: Data) -> ChannelInfoViewModel {
    ChannelInfoViewModel(
      channelId: channelId,
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeCreateChannelViewModel() -> CreateChannelViewModel {
    CreateChannelViewModel(
      messagingService: messagingRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }
}
