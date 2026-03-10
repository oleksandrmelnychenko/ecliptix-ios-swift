// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ContactSearchView: View {

  @State var viewModel: ContactSearchViewModel
  var onContactSelected: (Data) -> Void

  var body: some View {
    List {
      if viewModel.isSearching {
        HStack {
          Spacer()
          ProgressView()
          Spacer()
        }
      } else if viewModel.contacts.isEmpty && !viewModel.searchQuery.isEmpty {
        Text(String(localized: "No results found"))
          .font(.geistFootnote)
          .foregroundColor(.ecliptixSecondaryText)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 20)
      } else {
        ForEach(viewModel.contacts) { contact in
          Button {
            onContactSelected(contact.id)
          } label: {
            ContactListItem(contact: contact)
          }
          .buttonStyle(.plain)
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .navigationTitle(String(localized: "Search Contacts"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(
      text: $viewModel.searchQuery, prompt: String(localized: "Search by name or username"))
  }
}
