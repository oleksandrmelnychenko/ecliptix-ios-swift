// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ChannelInfoView: View {

  @State var viewModel: ChannelInfoViewModel
  var onNavigate: (MessagesNavigationDestination) -> Void
  @State private var isEditing = false

  var body: some View {
    List {
      headerSection
      statsSection

      if viewModel.isAdmin {
        settingsSection
      }

      adminsSection
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(EcliptixScreenBackground())
    .navigationTitle(String(localized: "Channel Info"))
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      if viewModel.isAdmin {
        ToolbarItem(placement: .topBarTrailing) {
          Button(isEditing ? String(localized: "Done") : String(localized: "Edit")) {
            if isEditing {
              Task { await viewModel.updateSettings() }
            }
            isEditing.toggle()
          }
        }
      }
    }
    .task { await viewModel.loadInfo() }
    .alert(String(localized: "Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var headerSection: some View {
    Section {
      VStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(Color.ecliptixAccent.gradient)
            .frame(width: 80, height: 80)
          Image(systemName: "megaphone.fill")
            .font(.system(size: 30, weight: .semibold))
            .foregroundStyle(.white)
        }

        if isEditing {
          TextField(String(localized: "Channel Name"), text: $viewModel.channelTitle)
            .font(.geist(.semiBold, size: 20))
            .multilineTextAlignment(.center)
          TextField(String(localized: "Description"), text: $viewModel.channelDescription, axis: .vertical)
            .font(.geistFootnote)
            .foregroundColor(.ecliptixSecondaryText)
            .multilineTextAlignment(.center)
        } else {
          Text(viewModel.channelTitle)
            .font(.geist(.semiBold, size: 20))
            .foregroundColor(.ecliptixPrimaryText)
          if !viewModel.channelDescription.isEmpty {
            Text(viewModel.channelDescription)
              .font(.geistFootnote)
              .foregroundColor(.ecliptixSecondaryText)
          }
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 12)
      .listRowBackground(Color.ecliptixSurface)
    }
  }

  private var statsSection: some View {
    Section {
      HStack {
        Text(String(localized: "Subscribers"))
          .font(.geist(.regular, size: 15))
          .foregroundColor(.ecliptixPrimaryText)
        Spacer()
        Text("\(viewModel.subscriberCount)")
          .font(.geist(.medium, size: 15))
          .foregroundColor(.ecliptixSecondaryText)
      }
      .listRowBackground(Color.ecliptixSurface)
    }
  }

  private var settingsSection: some View {
    Section(String(localized: "Settings")) {
      Toggle(String(localized: "Admin Signatures"), isOn: $viewModel.adminSignatures)
        .font(.geist(.regular, size: 15))
        .tint(.ecliptixAccent)
        .disabled(!isEditing)
        .listRowBackground(Color.ecliptixSurface)
    }
  }

  private var adminsSection: some View {
    Section(String(localized: "Admins")) {
      ForEach(viewModel.admins) { admin in
        Button {
          onNavigate(.userProfile(membershipId: admin.id))
        } label: {
          HStack(spacing: 12) {
            ZStack {
              Circle()
                .fill(Color.ecliptixAccent.gradient)
                .frame(width: 40, height: 40)
              Text(admin.displayName.initials)
                .font(.geist(.semiBold, size: 14))
                .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
              Text(admin.displayName)
                .font(.geist(.medium, size: 15))
                .foregroundColor(.ecliptixPrimaryText)
              Text(admin.role == .owner ? String(localized: "Owner") : String(localized: "Admin"))
                .font(.geistCaption)
                .foregroundColor(.ecliptixSecondaryText)
            }
          }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.ecliptixSurface)
      }
    }
  }
}
