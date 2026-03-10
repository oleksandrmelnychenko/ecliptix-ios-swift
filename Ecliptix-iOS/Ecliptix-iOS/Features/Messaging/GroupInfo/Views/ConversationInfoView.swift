import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ConversationInfoView: View {

  @State var viewModel: ConversationInfoViewModel
  var onNavigate: (MessagesNavigationDestination) -> Void
  @State private var showLeaveConfirmation = false
  @State private var memberToRemove: MemberDisplayItem?

  var body: some View {
    List {
      Section {
        VStack(spacing: 16) {
          GroupAvatarView(
            title: viewModel.conversationTitle, avatarUrl: viewModel.avatarUrl, size: 80)

          if viewModel.isGroup {
            Text(viewModel.conversationTitle)
              .font(.geist(.semiBold, size: 22))
              .foregroundColor(.ecliptixPrimaryText)

            if !viewModel.conversationDescription.isEmpty {
              Text(viewModel.conversationDescription)
                .font(.geistFootnote)
                .foregroundColor(.ecliptixSecondaryText)
                .multilineTextAlignment(.center)
            }

            Text(String(localized: "\(viewModel.members.count) members"))
              .font(.geistCaption)
              .foregroundColor(.ecliptixTertiaryText)
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .listRowBackground(Color.ecliptixBackground)
      }

      Section(String(localized: "Notifications")) {
        Button {
          Task {
            let newStatus: ProtoMuteStatus = viewModel.muteStatus == .unmuted ? .muted1D : .unmuted
            await viewModel.muteConversation(newStatus)
          }
        } label: {
          Label(
            viewModel.muteStatus == .unmuted
              ? String(localized: "Mute") : String(localized: "Unmute"),
            systemImage: viewModel.muteStatus == .unmuted ? "bell.slash" : "bell"
          )
        }
      }

      if viewModel.isGroup {
        Section {
          if viewModel.isAdmin {
            Button {
            } label: {
              Label(String(localized: "Add Members"), systemImage: "person.badge.plus")
                .foregroundColor(.ecliptixAccent)
            }
          }

          ForEach(viewModel.members) { member in
            MemberListItem(
              member: member,
              isAdmin: viewModel.isAdmin,
              onTap: {
                onNavigate(.userProfile(membershipId: member.id))
              },
              onRemove: viewModel.isAdmin
                ? {
                  memberToRemove = member
                } : nil
            )
          }
        } header: {
          Text(String(localized: "Members"))
        }
      }

      Section {
        if viewModel.isGroup {
          Button(role: .destructive) {
            showLeaveConfirmation = true
          } label: {
            Label(
              String(localized: "Leave Group"), systemImage: "rectangle.portrait.and.arrow.right"
            )
            .foregroundColor(.ecliptixDanger)
          }
        }
      }
    }
    .navigationTitle(
      viewModel.isGroup ? String(localized: "Group Info") : String(localized: "Contact Info")
    )
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.loadInfo() }
    .alert(String(localized: "Leave Group"), isPresented: $showLeaveConfirmation) {
      Button(String(localized: "Leave"), role: .destructive) {
        Task { await viewModel.leaveGroup() }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    } message: {
      Text(String(localized: "Are you sure you want to leave this group?"))
    }
    .alert(
      String(localized: "Remove Member"),
      isPresented: .init(
        get: { memberToRemove != nil },
        set: { if !$0 { memberToRemove = nil } }
      )
    ) {
      Button(String(localized: "Remove"), role: .destructive) {
        if let member = memberToRemove {
          Task { await viewModel.removeMember(member.id) }
          memberToRemove = nil
        }
      }
      Button(String(localized: "Cancel"), role: .cancel) { memberToRemove = nil }
    } message: {
      if let member = memberToRemove {
        Text(String(localized: "Remove \(member.displayName) from this group?"))
      }
    }
  }
}
