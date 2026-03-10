// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PhoneContactsView: View {

  @State var viewModel: PhoneContactsViewModel
  @State private var inviteMessage: String = ""
  @State private var showInviteSheet: Bool = false

  var body: some View {
    ZStack {
      EcliptixScreenBackground()
      content
    }
    .navigationTitle(String(localized: "Phone Contacts"))
    .navigationBarTitleDisplayMode(.inline)
    .searchable(text: Bindable(viewModel).searchQuery, prompt: String(localized: "Search contacts"))
    .task { await viewModel.loadContacts() }
    .sheet(isPresented: $showInviteSheet) {
      ActivityView(activityItems: [inviteMessage])
        .presentationDetents([.medium])
    }
  }

  @ViewBuilder
  private var content: some View {
    if viewModel.isLoading {
      VStack(spacing: 16) {
        ProgressView()
        Text(String(localized: "Loading contacts..."))
          .font(.geistSubheadline)
          .foregroundColor(.ecliptixSecondaryText)
      }
    } else if viewModel.isPermissionDenied {
      isPermissionDeniedView
    } else if viewModel.contacts.isEmpty {
      emptyState
    } else {
      contactsList
    }
  }

  private var contactsList: some View {
    List {
      if viewModel.matchedCount > 0 {
        Section {
          Text(String(format: String(localized: "%d contacts on Ecliptix"), viewModel.matchedCount))
            .font(.geistFootnote)
            .foregroundColor(.ecliptixSecondaryText)
            .listRowBackground(Color.clear)
        }
      }

      ForEach(viewModel.sections, id: \.letter) { section in
        Section(header: Text(section.letter)) {
          ForEach(section.contacts) { contact in
            PhoneContactRow(
              contact: contact,
              onTap: { viewModel.selectContact(contact) },
              onInvite: { presentInvite(for: contact) }
            )
          }
        }
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
  }

  private var isPermissionDeniedView: some View {
    VStack(spacing: 20) {
      Image(systemName: "person.crop.circle.badge.xmark")
        .font(.system(size: 56))
        .foregroundColor(.ecliptixSecondaryText)
        .accessibilityHidden(true)
      Text(String(localized: "Contacts Access Required"))
        .font(.geist(.semiBold, size: 20))
        .foregroundColor(.ecliptixPrimaryText)
      Text(String(localized: "Allow access to your contacts to find friends on Ecliptix"))
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Button {
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url)
        }
      } label: {
        Text(String(localized: "Open Settings"))
          .font(.geist(.semiBold, size: 17))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 15)
          .foregroundColor(.ecliptixPrimaryButtonText)
          .background(Color.ecliptixPrimaryButton)
          .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .padding(.horizontal, 40)
    }
  }

  private var emptyState: some View {
    VStack(spacing: 16) {
      Image(systemName: "person.2.slash")
        .font(.system(size: 48))
        .foregroundColor(.ecliptixSecondaryText)
        .accessibilityHidden(true)
      Text(String(localized: "No contacts found"))
        .font(.geist(.medium, size: 18))
        .foregroundColor(.ecliptixSecondaryText)
    }
  }

  private func presentInvite(for contact: PhoneContact) {
    inviteMessage = String(
      format: String(
        localized:
          "Hey %@! Join me on Ecliptix — a secure messenger. Download it here: https://ecliptix.app"
      ),
      contact.fullName
    )
    showInviteSheet = true
  }
}

struct ActivityView: UIViewControllerRepresentable {

  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
