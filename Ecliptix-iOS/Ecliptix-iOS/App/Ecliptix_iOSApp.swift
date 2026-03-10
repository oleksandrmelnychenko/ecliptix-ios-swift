import SwiftUI
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import os.log

@main
struct Ecliptix_iOSApp: App {

  @AppStorage("app_theme") private var appThemeRawValue: String = AppTheme.light.rawValue
  @AppStorage("accent_color") private var accentColorRawValue: String = AccentColor.green.rawValue
  init() {
    setupApp()
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .preferredColorScheme(selectedTheme.colorScheme)
        .tint(selectedAccent.color)
    }
  }

  private var selectedTheme: AppTheme {
    AppTheme(rawValue: appThemeRawValue) ?? .light
  }

  private var selectedAccent: AccentColor {
    AccentColor(rawValue: accentColorRawValue) ?? .green
  }

  private func setupApp() {
    AppLogger.app.info("\(StartupBranding.appName, privacy: .public) iOS launching...")
    AppLogger.app.debug(
      "startup env=\(StartupRuntime.environment.rawValue, privacy: .public) logo=\(StartupAssetName.splashLogo.rawValue, privacy: .public)"
    )
    AppLogger.app.debug(
      "iconSet=\(StartupAssetName.appIconSet.rawValue, privacy: .public) bg=\(StartupBranding.splashBackgroundHex, privacy: .public) marker=\(StartupRuntime.buildMarker, privacy: .public)"
    )
  }
}
