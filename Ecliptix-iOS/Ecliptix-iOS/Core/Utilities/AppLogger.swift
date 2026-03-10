// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

enum AppLogger {

  static let app = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "App")
  static let network = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Network")
  static let security = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Security")
  static let auth = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Auth")
  static let ui = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "UI")
  static let messaging = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Messaging")
  static let storage = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Storage")
  static let sync = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Sync")
  static let crypto = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Crypto")
  static let feed = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app", category: "Feed")
}
