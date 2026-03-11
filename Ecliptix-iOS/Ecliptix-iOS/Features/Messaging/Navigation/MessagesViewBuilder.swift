// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

@MainActor
enum MessagesViewBuilder {

  @ViewBuilder
  static func destination(
    for destination: MessagesNavigationDestination,
    coordinator: AppCoordinator,
    path: Binding<[MessagesNavigationDestination]>
  ) -> some View {
    switch destination {
    case .chatDetail(let conversationId):
      ChatDetailView(
        viewModel: coordinator.dependencies.makeChatDetailViewModel(conversationId: conversationId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    case .newConversation:
      NewConversationView(
        viewModel: coordinator.dependencies.makeNewConversationViewModel(),
        onConversationSelected: { conversationId in
          path.wrappedValue.append(.chatDetail(conversationId: conversationId))
        },
        onNewGroup: {
          path.wrappedValue.append(.newGroup)
        },
        onNewChannel: {
          path.wrappedValue.append(.channelCreation)
        },
        onPhoneContacts: {
          path.wrappedValue.append(.phoneContacts)
        }
      )
    case .newGroup:
      NewGroupView(
        viewModel: coordinator.dependencies.makeNewGroupViewModel(),
        onContinue: { memberIds in
          path.wrappedValue.append(.groupCreation(memberIds: memberIds))
        }
      )
    case .groupCreation(let memberIds):
      GroupCreationView(
        viewModel: coordinator.dependencies.makeGroupCreationViewModel(memberIds: memberIds),
        onGroupCreated: { conversationId in
          path.wrappedValue = [.chatDetail(conversationId: conversationId)]
        }
      )
    case .conversationInfo(let conversationId):
      ConversationInfoView(
        viewModel: coordinator.dependencies.makeConversationInfoViewModel(
          conversationId: conversationId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    case .userProfile(let membershipId):
      UserProfileView(
        viewModel: coordinator.dependencies.makeUserProfileViewModel(membershipId: membershipId),
        onSendMessage: { conversationId in
          path.wrappedValue = [.chatDetail(conversationId: conversationId)]
        }
      )
    case .contactSearch:
      ContactSearchView(
        viewModel: coordinator.dependencies.makeContactSearchViewModel(),
        onContactSelected: { conversationId in
          path.wrappedValue.append(.chatDetail(conversationId: conversationId))
        }
      )
    case .phoneContacts:
      PhoneContactsView(
        viewModel: coordinator.dependencies.makePhoneContactsViewModel(
          onContactSelected: { membershipId in
            path.wrappedValue.append(.userProfile(membershipId: membershipId))
          }
        )
      )
    case .channelFeed(let channelId):
      ChannelFeedView(
        viewModel: coordinator.dependencies.makeChannelFeedViewModel(channelId: channelId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    case .channelInfo(let channelId):
      ChannelInfoView(
        viewModel: coordinator.dependencies.makeChannelInfoViewModel(channelId: channelId),
        onNavigate: { dest in path.wrappedValue.append(dest) }
      )
    case .channelCreation:
      CreateChannelView(
        viewModel: coordinator.dependencies.makeCreateChannelViewModel(),
        onChannelCreated: { channelId in
          path.wrappedValue.append(.channelFeed(channelId: channelId))
        }
      )
    case .addMembers(let conversationId):
      NewGroupView(
        viewModel: coordinator.dependencies.makeNewGroupViewModel(),
        onContinue: { memberIds in
          let vm = coordinator.dependencies.makeConversationInfoViewModel(
            conversationId: conversationId)
          Task {
            await vm.addMembers(memberIds)
            path.wrappedValue.removeLast()
          }
        }
      )
      .navigationTitle(String(localized: "Add Members"))
    }
  }
}
