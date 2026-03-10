// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct LogoutButton: View {

  @State private var showLogoutSheet: Bool = false
  let logoutService: LogoutService
  let onLogoutComplete: () -> Void
  var body: some View {
    Button(action: {
      showLogoutSheet = true
    }) {
      HStack {
        Image(systemName: "arrow.right.square")
          .foregroundColor(.ecliptixDanger)
          .accessibilityHidden(true)
        Text(String(localized: "Sign Out"))
          .foregroundColor(.ecliptixDanger)
        Spacer()
      }
      .padding(.vertical, 12)
      .frame(minHeight: 44)
    }
    .accessibilityLabel(Text(String(localized: "Sign Out")))
    .accessibilityHint(Text(String(localized: "Opens sign out confirmation")))
    .sheet(isPresented: $showLogoutSheet) {
      LogoutConfirmationView(
        viewModel: LogoutViewModel(logoutService: logoutService),
        onLogoutComplete: onLogoutComplete
      )
      .presentationDetents([.height(420)])
      .presentationDragIndicator(.visible)
    }
  }
}
