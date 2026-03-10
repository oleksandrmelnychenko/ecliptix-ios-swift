// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum AppErrorMessages {

  static let settingsInitializationFailed = String(localized: "Settings initialization failed")
  static let secrecyChannelFailed = String(localized: "Secrecy channel initialization failed")
  static let deviceRegistrationFailed = String(localized: "Device registration failed")
  static let initializationFailed = String(localized: "Initialization Failed")
  static let startupConnectionIssue = String(
    localized: "Cannot connect to the server. Please check your internet connection and try again."
  )
  static let startupGenericIssue = String(
    localized: "Something went wrong while starting the app. Please try again."
  )
}
