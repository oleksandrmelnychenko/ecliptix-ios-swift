// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ErrorView: View {

  let message: String
  var coordinator: AppCoordinator
  var body: some View {
    VStack(spacing: 24) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixDanger)
        .accessibilityHidden(true)
      Text(AppErrorMessages.initializationFailed)
        .font(.geistTitle2)
      Text(message)
        .font(.geistSubheadline)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 32)
      Button("Retry") {
        Task { await coordinator.startup(settings: coordinator.dependencies.settings) }
      }
      .disabled(coordinator.isStartupInProgress)
      .buttonStyle(.borderedProminent)
      .frame(minWidth: 44, minHeight: 44)
    }
  }
}
