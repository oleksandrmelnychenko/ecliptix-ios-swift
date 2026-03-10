// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct MainTabView: View {

  var coordinator: AppCoordinator
  var accountViewModel: AccountSettingsViewModel
  @State private var feedViewModel: FeedListViewModel
  @State private var conversationViewModel: ConversationListViewModel
  @State private var feedPath: [FeedNavigationDestination] = []
  @State private var messagesPath: [MessagesNavigationDestination] = []
  @State private var selectedTab: Int = 0

  init(coordinator: AppCoordinator, accountViewModel: AccountSettingsViewModel) {
    self.coordinator = coordinator
    self.accountViewModel = accountViewModel
    self._feedViewModel = State(wrappedValue: coordinator.dependencies.makeFeedListViewModel())
    self._conversationViewModel = State(
      wrappedValue: coordinator.dependencies.makeConversationListViewModel())
  }

  var body: some View {
    TabView(selection: $selectedTab) {
      NavigationStack(path: $feedPath) {
        FeedListView(
          viewModel: feedViewModel,
          onNavigate: { destination in feedPath.append(destination) }
        )
        .navigationDestination(for: FeedNavigationDestination.self) { destination in
          FeedViewBuilder.destination(
            for: destination,
            coordinator: coordinator,
            path: $feedPath
          )
        }
      }
      .tabItem { Label(String(localized: "Feed"), systemImage: "text.bubble.fill") }
      .tag(0)
      NavigationStack(path: $messagesPath) {
        ConversationListView(
          viewModel: conversationViewModel,
          onNavigate: { destination in messagesPath.append(destination) }
        )
        .navigationDestination(for: MessagesNavigationDestination.self) { destination in
          MessagesViewBuilder.destination(
            for: destination,
            coordinator: coordinator,
            path: $messagesPath
          )
        }
      }
      .tabItem { Label(String(localized: "Messages"), systemImage: "message.fill") }
      .tag(1)
      NavigationStack {
        SettingsView(coordinator: coordinator, accountViewModel: accountViewModel)
      }
      .tabItem { Label(String(localized: "Settings"), systemImage: "gear") }
      .tag(2)
    }
  }
}
