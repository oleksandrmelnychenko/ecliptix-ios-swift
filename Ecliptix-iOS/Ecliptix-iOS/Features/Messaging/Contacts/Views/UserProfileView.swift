// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct UserProfileView: View {

  @State var viewModel: UserProfileViewModel
  var onSendMessage: (Data) -> Void
  @State private var showBlockConfirmation = false

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      VStack(spacing: 24) {
        ZStack {
          Circle()
            .fill(Color.ecliptixAccent.gradient)
            .frame(width: 100, height: 100)
          Text(initials)
            .font(.geist(.semiBold, size: 36))
            .foregroundStyle(.white)
        }
        .padding(.top, 32)

        VStack(spacing: 4) {
          Text(viewModel.displayName)
            .font(.geist(.semiBold, size: 22))
            .foregroundColor(.ecliptixPrimaryText)
          Text("@\(viewModel.profileName)")
            .font(.geistFootnote)
            .foregroundColor(.ecliptixSecondaryText)
        }

        VStack(spacing: 12) {
          Button {
            Task {
              if let id = await viewModel.createConversation() {
                onSendMessage(id)
              }
            }
          } label: {
            Text(String(localized: "Send Message"))
              .font(.geist(.semiBold, size: 16))
              .frame(maxWidth: .infinity)
              .frame(height: 46)
              .foregroundColor(.ecliptixPrimaryButtonText)
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

          Button {
            showBlockConfirmation = true
          } label: {
            Text(viewModel.isBlocked ? String(localized: "Unblock") : String(localized: "Block"))
              .font(.geist(.medium, size: 15))
              .frame(maxWidth: .infinity)
              .frame(height: 46)
              .foregroundColor(.ecliptixDanger)
              .background(Color.ecliptixDanger.opacity(0.1))
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)

        Spacer()
      }
    }
    .navigationTitle(String(localized: "Profile"))
    .navigationBarTitleDisplayMode(.inline)
    .task { await viewModel.loadProfile() }
    .alert(
      viewModel.isBlocked ? String(localized: "Unblock User") : String(localized: "Block User"),
      isPresented: $showBlockConfirmation
    ) {
      Button(
        viewModel.isBlocked ? String(localized: "Unblock") : String(localized: "Block"),
        role: .destructive
      ) {
        Task { await viewModel.toggleBlock() }
      }
      Button(String(localized: "Cancel"), role: .cancel) {}
    }
  }

  private var initials: String {
    viewModel.displayName.initials
  }
}
