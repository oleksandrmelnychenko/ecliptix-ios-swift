// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct LogoutConfirmationView: View {

  @State private var viewModel: LogoutViewModel
  @Environment(\.dismiss) private var dismiss
  let onLogoutComplete: () -> Void

  init(
    viewModel: LogoutViewModel,
    onLogoutComplete: @escaping () -> Void
  ) {
    _viewModel = State(wrappedValue: viewModel)
    self.onLogoutComplete = onLogoutComplete
  }

  var body: some View {
    @Bindable var vm = viewModel
    ZStack {
      Color(.label).opacity(0.4)
        .ignoresSafeArea()
        .onTapGesture {
          if !viewModel.isLoggingOut {
            dismiss()
          }
        }
      VStack(spacing: 0) {
        Spacer()
        dialogContent
          .background(Color(.systemBackground))
          .cornerRadius(16, corners: [.topLeft, .topRight])
          .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: -5)
      }
    }
    .alert(String(localized: "Logout Error"), isPresented: $vm.hasError) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var dialogContent: some View {
    VStack(spacing: 24) {
      handleBar
      if viewModel.isLoggingOut {
        loggingOutContent
      } else {
        confirmationContent
      }
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 32)
  }

  private var handleBar: some View {
    RoundedRectangle(cornerRadius: 3)
      .fill(Color.ecliptixMutedStroke)
      .frame(width: 40, height: 5)
      .accessibilityHidden(true)
  }

  private var confirmationContent: some View {
    VStack(spacing: 24) {
      Image(systemName: "arrow.right.square.fill")
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixDanger)
        .accessibilityHidden(true)
      VStack(spacing: 12) {
        Text(String(localized: "Sign Out?"))
          .font(.geist(.bold, size: 28))
        Text(String(localized: "You'll need to sign in again to access your account"))
          .font(.geistSubheadline)
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
      }
      VStack(spacing: 12) {
        Button(action: {
          Task {
            await viewModel.confirmLogout()
            guard !viewModel.hasError else { return }
            onLogoutComplete()
          }
        }) {
          Text(String(localized: "Sign Out"))
            .font(.geist(.semiBold, size: 17))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundColor(.ecliptixPrimaryButtonText)
            .background(Color.ecliptixDanger)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(minHeight: 44)
        Button(action: {
          dismiss()
        }) {
          Text(String(localized: "Cancel"))
            .font(.geist(.semiBold, size: 17))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .foregroundColor(.ecliptixAccent)
            .background(Color.ecliptixSecondaryButton)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(minHeight: 44)
      }
    }
  }

  private var loggingOutContent: some View {
    VStack(spacing: 24) {
      ProgressView()
        .scaleEffect(1.5)
        .padding(.vertical, 20)
      VStack(spacing: 12) {
        Text(String(localized: "Signing Out..."))
          .font(.geistTitle3)
        Text(String(localized: "Securely clearing your data"))
          .font(.geistSubheadline)
          .foregroundColor(.secondary)
      }
      VStack(alignment: .leading, spacing: 12) {
        logoutStep(
          icon: "checkmark.circle.fill",
          text: "Notifying server",
          isComplete: true
        )
        logoutStep(
          icon: "checkmark.circle.fill",
          text: "Clearing local data",
          isComplete: true
        )
        logoutStep(
          icon: "circle",
          text: "Finalizing...",
          isComplete: false
        )
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 20)
      .background(Color.ecliptixSurface.opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }

  private func logoutStep(icon: String, text: LocalizedStringKey, isComplete: Bool) -> some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundColor(isComplete ? .ecliptixSuccess : .secondary)
        .font(.geist(.semiBold, size: 17))
        .accessibilityHidden(true)
      Text(text)
        .font(.geistSubheadline)
        .foregroundColor(isComplete ? .primary : .secondary)
      Spacer()
    }
  }
}

#Preview("Confirmation") {
  LogoutConfirmationView(
    viewModel: AppDependencies.shared.makeLogoutViewModel(),
    onLogoutComplete: {}
  )
}
