import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ConversationListView: View {

  @State var viewModel: ConversationListViewModel
  @State private var composeAppearTrigger = 0
  var onNavigate: (MessagesNavigationDestination) -> Void

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      if viewModel.isLoading && viewModel.conversations.isEmpty {
        ProgressView()
          .tint(.ecliptixAccent)
      } else if viewModel.conversations.isEmpty && !viewModel.isLoading {
        emptyState
      } else {
        conversationList
      }
    }
    .navigationTitle(String(localized: "Messages"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          onNavigate(.newConversation)
        } label: {
          Image(systemName: "square.and.pencil")
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.ecliptixAccent)
            .symbolEffect(.bounce, value: composeAppearTrigger)
        }
        .accessibilityLabel(Text(String(localized: "New conversation")))
        .accessibilityHint(Text(String(localized: "Start a new conversation")))
      }
    }
    .searchable(
      text: $viewModel.searchQuery,
      prompt: String(localized: "Search conversations")
    )
    .refreshable {
      await viewModel.refreshConversations()
    }
    .task {
      viewModel.startObservingRealtimeUpdates()
      await viewModel.loadConversations()
    }
    .onAppear { composeAppearTrigger += 1 }
    .onDisappear {
      viewModel.stopObservingRealtimeUpdates()
    }
    .alert(
      String(localized: "Error"),
      isPresented: $viewModel.hasError
    ) {
      Button(String(localized: "Retry")) {
        Task { await viewModel.loadConversations() }
      }
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var conversationList: some View {
    List {
      if !viewModel.pinnedConversations.isEmpty {
        Section {
          ForEach(viewModel.pinnedConversations) { conversation in
            conversationRow(conversation)
          }
        } header: {
          Text(String(localized: "Pinned"))
            .font(.geist(.semiBold, size: 12))
            .foregroundColor(.ecliptixSecondaryText)
            .textCase(nil)
        }
      }

      Section {
        ForEach(viewModel.regularConversations) { conversation in
          conversationRow(conversation)
        }
      } header: {
        if !viewModel.pinnedConversations.isEmpty {
          Text(String(localized: "Recent"))
            .font(.geist(.semiBold, size: 12))
            .foregroundColor(.ecliptixSecondaryText)
            .textCase(nil)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private func conversationRow(_ conversation: ConversationDisplayItem) -> some View {
    Button {
      if conversation.isChannel {
        onNavigate(.channelFeed(channelId: conversation.id))
      } else {
        onNavigate(.chatDetail(conversationId: conversation.id))
      }
    } label: {
      ConversationCellView(conversation: conversation)
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
      Button(role: .destructive) {
        Task { await viewModel.deleteConversation(conversation.id) }
      } label: {
        Label(String(localized: "Delete"), systemImage: "trash.fill")
      }
      .tint(.ecliptixDanger)

      Button {
        Task { await viewModel.archiveConversation(conversation.id) }
      } label: {
        Label(String(localized: "Archive"), systemImage: "archivebox.fill")
      }
      .tint(.ecliptixAccent)
    }
    .swipeActions(edge: .leading, allowsFullSwipe: false) {
      Button {
        Task {
          if conversation.isPinned {
            await viewModel.unpinConversation(conversation.id)
          } else {
            await viewModel.pinConversation(conversation.id)
          }
        }
      } label: {
        Label(
          conversation.isPinned
            ? String(localized: "Unpin")
            : String(localized: "Pin"),
          systemImage: conversation.isPinned ? "pin.slash.fill" : "pin.fill"
        )
      }
      .tint(.ecliptixAccent)

      Button {
        Task {
          let newStatus: ProtoMuteStatus = conversation.isMuted ? .unmuted : .mutedForever
          await viewModel.muteConversation(conversation.id, status: newStatus)
        }
      } label: {
        Label(
          conversation.isMuted
            ? String(localized: "Unmute")
            : String(localized: "Mute"),
          systemImage: conversation.isMuted ? "bell.fill" : "bell.slash.fill"
        )
      }
      .tint(.ecliptixSecondaryButton)
    }
    .listRowBackground(Color.ecliptixBackground)
    .listRowSeparatorTint(.ecliptixMutedStroke)
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "message.fill")
        .font(.system(size: 48))
        .foregroundColor(.ecliptixTertiaryText)
        .accessibilityHidden(true)

      Text(String(localized: "No Conversations"))
        .font(.geist(.semiBold, size: 20))
        .foregroundColor(.ecliptixPrimaryText)

      Text(String(localized: "Start a new conversation to begin messaging"))
        .font(.geistFootnote)
        .foregroundColor(.ecliptixSecondaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 48)

      Button {
        onNavigate(.newConversation)
      } label: {
        Text(String(localized: "New Message"))
          .font(.geist(.medium, size: 15))
          .foregroundColor(.ecliptixPrimaryButtonText)
          .padding(.horizontal, 24)
          .padding(.vertical, 12)
          .background(
            LinearGradient(
              colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .padding(.top, 8)
    }
  }
}
