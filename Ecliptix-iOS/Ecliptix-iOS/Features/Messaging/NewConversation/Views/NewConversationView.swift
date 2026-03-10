// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct NewConversationView: View {

  @State var viewModel: NewConversationViewModel
  var onConversationSelected: (Data) -> Void
  var onNewGroup: () -> Void
  var onNewChannel: () -> Void
  var onPhoneContacts: () -> Void

  var body: some View {
    List {
      Section {
        Button {
          onNewGroup()
        } label: {
          Label(String(localized: "New Group"), systemImage: "person.3")
            .foregroundColor(.ecliptixAccent)
        }
        Button {
          onNewChannel()
        } label: {
          Label(String(localized: "New Channel"), systemImage: "megaphone")
            .foregroundColor(.ecliptixAccent)
        }
        Button {
          onPhoneContacts()
        } label: {
          Label(String(localized: "Phone Contacts"), systemImage: "person.crop.rectangle.stack")
            .foregroundColor(.ecliptixAccent)
        }
      }

      Section(String(localized: "Contacts")) {
        if viewModel.isLoading {
          HStack {
            Spacer()
            ProgressView()
            Spacer()
          }
        } else if viewModel.filteredContacts.isEmpty {
          Text(String(localized: "No contacts found"))
            .font(.geistFootnote)
            .foregroundColor(.ecliptixSecondaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 20)
        } else {
          ForEach(viewModel.filteredContacts) { contact in
            Button {
              Task {
                if let conversationId = await viewModel.createDirectConversation(with: contact.id) {
                  onConversationSelected(conversationId)
                }
              }
            } label: {
              ContactListItem(contact: contact)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isCreatingConversation)
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .navigationTitle(String(localized: "New Message"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: $viewModel.searchQuery, prompt: String(localized: "Search contacts"))
    .task { await viewModel.loadContacts() }
  }
}
