// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct AccountSettingsView: View {

  @Bindable var viewModel: AccountSettingsViewModel
  var body: some View {
    List {
      avatarSection
      displayNameSection
      profileInfoSection
    }
    .navigationTitle(String(localized: "Account"))
    .overlay {
      if viewModel.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .background(Color.ecliptixBackground.opacity(0.85))
      }
    }
    .alert(String(localized: "Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK")) {}
    } message: {
      Text(viewModel.errorMessage)
    }
    .task { await viewModel.loadProfile() }
    .onDisappear {
      viewModel.cancelPendingTasks()
    }
  }

  private var avatarSection: some View {
    Section {
      HStack {
        Spacer()
        ZStack {
          Circle()
            .fill(Color.ecliptixAccent.gradient)
            .frame(width: 80, height: 80)
          Text(viewModel.profileInitials)
            .font(.geist(.semiBold, size: 28))
            .foregroundStyle(.white)
        }
        Spacer()
      }
      .listRowBackground(Color.clear)
      .padding(.vertical, 8)
    }
  }

  private var displayNameSection: some View {
    Section {
      VStack(alignment: .leading, spacing: 6) {
        Text(String(localized: "Display Name"))
          .font(.geistFootnote)
          .foregroundStyle(.secondary)
        TextField(String(localized: "John Doe"), text: $viewModel.displayName)
          .textContentType(.name)
          .autocorrectionDisabled()
        if viewModel.hasDisplayNameError {
          Text(viewModel.displayNameError)
            .font(.geistCaption)
            .foregroundStyle(Color.ecliptixDanger)
        }
      }
      HStack {
        if viewModel.isSaving {
          ProgressView()
            .controlSize(.small)
          Text(String(localized: "Saving..."))
            .font(.geistCaption)
            .foregroundStyle(.secondary)
        } else if viewModel.showSavedConfirmation {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Color.ecliptixSuccess)
          Text(String(localized: "Saved"))
            .font(.geistCaption)
            .foregroundStyle(Color.ecliptixSuccess)
        }
      }
      .animation(.ecliptixSnappy, value: viewModel.isSaving)
      .animation(.ecliptixSnappy, value: viewModel.showSavedConfirmation)
    } footer: {
      Text(String(localized: "Visible to other users"))
        .font(.geistCaption)
    }
  }

  private var profileInfoSection: some View {
    Section(String(localized: "Profile")) {
      if !viewModel.handle.isEmpty {
        HStack {
          Label(String(localized: "Handle"), systemImage: "at")
          Spacer()
          Text(viewModel.handle)
            .foregroundStyle(.secondary)
        }
      }
      if !viewModel.mobileNumber.isEmpty {
        HStack {
          Label(String(localized: "Mobile Number"), systemImage: "phone")
          Spacer()
          Text(viewModel.mobileNumber)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}
