// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ChatDetailView: View {

  @Bindable var viewModel: ChatDetailViewModel
  var onNavigate: (MessagesNavigationDestination) -> Void

  @FocusState private var isInputFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      messageList

      if viewModel.isTyping {
        typingBar
      }

      if viewModel.replyingToMessage != nil {
        replyBar
      }

      ChatInputBar(
        text: $viewModel.inputText,
        isSending: viewModel.isSending,
        isInputFocused: $isInputFocused,
        onSend: {
          Task { await viewModel.sendMessage() }
        },
        onAttach: {
        }
      )
    }
    .background(EcliptixScreenBackground())
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.startObservingIncomingMessages()
    }
    .onDisappear {
      viewModel.stopObservingIncomingMessages()
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        headerView
      }
    }
    .task {
      await viewModel.loadInitialMessages()
      await viewModel.markAsRead()
    }
  }

  private var headerView: some View {
    Button {
      if viewModel.isGroup {
        onNavigate(.conversationInfo(conversationId: viewModel.conversationId))
      }
    } label: {
      HStack(spacing: 10) {
        avatarView

        VStack(alignment: .leading, spacing: 1) {
          Text(viewModel.conversationTitle)
            .font(.geist(.semiBold, size: 16))
            .foregroundColor(.ecliptixPrimaryText)
            .lineLimit(1)

          if viewModel.isTyping {
            Text(String(localized: "typing..."))
              .font(.geistCaption)
              .foregroundColor(.ecliptixAccent)
          } else if viewModel.isGroup {
            Text(String(localized: "tap for group info"))
              .font(.geistCaption)
              .foregroundColor(.ecliptixSecondaryText)
          } else {
            Text(
              viewModel.isOnline
                ? String(localized: "online")
                : String(localized: "offline")
            )
            .font(.geistCaption)
            .foregroundColor(
              viewModel.isOnline
                ? .ecliptixAccent
                : .ecliptixSecondaryText)
          }
        }
      }
    }
    .buttonStyle(.plain)
  }

  private var avatarView: some View {
    ZStack {
      Circle()
        .fill(Color.ecliptixAccent.opacity(0.15))
        .frame(width: 36, height: 36)

      Text(avatarInitials)
        .font(.geist(.semiBold, size: 14))
        .foregroundColor(.ecliptixAccent)
    }
    .overlay(alignment: .bottomTrailing) {
      if !viewModel.isGroup && viewModel.isOnline {
        Circle()
          .fill(Color.ecliptixOnlineIndicator)
          .frame(width: 10, height: 10)
          .overlay(
            Circle()
              .stroke(Color.ecliptixBackground, lineWidth: 2)
          )
          .offset(x: 2, y: 2)
      }
    }
  }

  private var avatarInitials: String {
    viewModel.conversationTitle.initials
  }

  private var messageList: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 2) {
          if viewModel.isLoading && viewModel.messages.isEmpty {
            loadingPlaceholder
          }

          if viewModel.hasMoreMessages && !viewModel.messages.isEmpty {
            loadMoreTrigger
          }

          ForEach(groupedMessages, id: \.date) { group in
            DateSeparatorView(date: group.date)
              .padding(.vertical, 8)

            ForEach(group.messages) { message in
              MessageBubbleView(
                message: message,
                isGroupChat: viewModel.isGroup
              )
              .id(message.id)
              .contextMenu {
                messageContextMenu(for: message)
              }
              .padding(.horizontal, 12)
              .padding(.vertical, 1)
              .transition(
                .asymmetric(
                  insertion: .scale(
                    scale: 0.9, anchor: message.isOwnMessage ? .bottomTrailing : .bottomLeading
                  )
                  .combined(with: .opacity),
                  removal: .opacity
                )
              )
            }
          }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
      }
      .scrollDismissesKeyboard(.interactively)
      .onChange(of: viewModel.messages.count) {
        if let lastId = viewModel.messages.last?.id {
          withAnimation(.ecliptixSmooth) {
            proxy.scrollTo(lastId, anchor: .bottom)
          }
        }
      }
    }
  }

  private var loadingPlaceholder: some View {
    VStack(spacing: 12) {
      ProgressView()
        .tint(.ecliptixSecondaryText)
      Text(String(localized: "Loading messages..."))
        .font(.geistCaption)
        .foregroundColor(.ecliptixTertiaryText)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private var loadMoreTrigger: some View {
    ProgressView()
      .tint(.ecliptixSecondaryText)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .task {
        await viewModel.loadMoreMessages()
      }
  }

  private var groupedMessages: [ChatMessageGroup] {
    viewModel.cachedGroupedMessages
  }

  @ViewBuilder
  private func messageContextMenu(for message: MessageDisplayItem) -> some View {
    Button {
      viewModel.setReplyTarget(message)
    } label: {
      Label(String(localized: "Reply"), systemImage: "arrowshape.turn.up.left")
    }

    if message.contentType == .text {
      Button {
        UIPasteboard.general.string = message.textContent
      } label: {
        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
      }
    }

    Divider()

    if message.isOwnMessage {
      Button(role: .destructive) {
        Task { await viewModel.deleteMessage(message.id, forEveryone: true) }
      } label: {
        Label(String(localized: "Delete for Everyone"), systemImage: "trash")
      }
    }

    Button(role: .destructive) {
      Task { await viewModel.deleteMessage(message.id, forEveryone: false) }
    } label: {
      Label(String(localized: "Delete for Me"), systemImage: "trash")
    }
  }

  private var typingBar: some View {
    HStack(spacing: 8) {
      TypingIndicatorView()
      Text("\(viewModel.typingUserName) " + String(localized: "is typing..."))
        .font(.geistCaption)
        .foregroundColor(.ecliptixSecondaryText)
      Spacer()
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 6)
    .background(Color.ecliptixSurface)
  }

  private var replyBar: some View {
    HStack(spacing: 10) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(Color.ecliptixAccent)
        .frame(width: 3, height: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(viewModel.replyingToMessage?.senderDisplayName ?? "")
          .font(.geist(.semiBold, size: 12))
          .foregroundColor(.ecliptixAccent)
          .lineLimit(1)

        Text(viewModel.replyingToMessage?.textContent ?? "")
          .font(.geistCaption)
          .foregroundColor(.ecliptixSecondaryText)
          .lineLimit(1)
      }

      Spacer()

      Button {
        viewModel.setReplyTarget(nil)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.geist(.medium, size: 18))
          .foregroundColor(.ecliptixTertiaryText)
      }
      .buttonStyle(.plain)
      .accessibilityLabel(Text(String(localized: "Cancel reply")))
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.ecliptixSurface)
  }
}
