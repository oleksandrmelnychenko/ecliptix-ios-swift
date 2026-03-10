// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct NewGroupView: View {

  @State var viewModel: NewGroupViewModel
  var onContinue: ([Data]) -> Void

  var body: some View {
    VStack(spacing: 0) {
      if !viewModel.selectedMembers.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(viewModel.selectedMembers) { member in
              HStack(spacing: 4) {
                Text(member.displayName)
                  .font(.geist(.medium, size: 13))
                  .foregroundColor(.ecliptixPrimaryText)
                Button {
                  viewModel.toggleMember(member.id)
                } label: {
                  Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.ecliptixTertiaryText)
                }
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 6)
              .background(Color.ecliptixSurface)
              .clipShape(Capsule())
              .overlay(
                Capsule().stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
              )
            }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
        }
        .background(Color.ecliptixBackground)

        Divider().foregroundColor(.ecliptixMutedStroke)
      }

      List {
        if viewModel.isLoading {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else {
          ForEach(viewModel.filteredContacts) { contact in
            Button {
              viewModel.toggleMember(contact.id)
            } label: {
              HStack(spacing: 12) {
                ContactListItem(contact: contact)
                Spacer()
                if viewModel.selectedMemberIds.contains(contact.id) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.ecliptixAccent)
                    .font(.system(size: 22))
                } else {
                  Circle()
                    .stroke(Color.ecliptixMutedStroke, lineWidth: 1.5)
                    .frame(width: 22, height: 22)
                }
              }
            }
            .buttonStyle(.plain)
          }
        }
      }
      .listStyle(.plain)
      .scrollContentBackground(.hidden)
    }
    .navigationTitle(String(localized: "Select Members"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $viewModel.searchQuery, prompt: String(localized: "Search contacts"))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(String(localized: "Next")) {
          onContinue(Array(viewModel.selectedMemberIds))
        }
        .font(.geist(.semiBold, size: 15))
        .foregroundColor(.ecliptixAccent)
        .disabled(!viewModel.canContinue)
      }
    }
    .task { await viewModel.loadContacts() }
  }
}
