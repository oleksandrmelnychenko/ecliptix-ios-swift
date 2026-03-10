// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension AppDependencies {

  @MainActor
  func makeLogoutViewModel() -> LogoutViewModel {
    LogoutViewModel(logoutService: logoutService)
  }

  @MainActor
  func makeAccountSettingsViewModel() -> AccountSettingsViewModel {
    AccountSettingsViewModel(
      profileService: profileRpcService,
      settingsProvider: weakSettingsProvider(),
      connectIdProvider: weakConnectIdProvider()
    )
  }

  @MainActor
  func makeOutboxDiagnosticsViewModel() -> OutboxDiagnosticsViewModel {
    OutboxDiagnosticsViewModel(
      databaseProvider: accountScopedDatabaseProvider
    )
  }
}
