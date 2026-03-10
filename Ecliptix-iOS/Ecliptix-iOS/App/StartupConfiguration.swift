// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI

enum StartupEnvironment: String {
  case development = "development"
  case staging = "staging"
  case production = "production"
}

enum StartupAssetName: String {
  case splashLogo = "EcliptixLogo"
  case appIconSet = "AppIcon"
}

enum StartupBranding {

  static let appName = "Ecliptix"
  static let splashBackgroundHex = "#FFFFFF"
  static var splashBackgroundColor: Color { .white }
}

enum StartupRuntime {

  static let environment: StartupEnvironment = .development
  static let buildMarker = "svg-logo-startup-v1"
}
