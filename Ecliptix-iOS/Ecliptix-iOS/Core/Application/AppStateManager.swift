// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

protocol ApplicationStateTransitioning: AnyObject {

  var currentState: ApplicationState { get }

  func transitionToAnonymous() async

  func transitionToAuthenticated(membershipId: String) async
}

enum ApplicationState: String, Codable {
  case initializing = "INITIALIZING"
  case anonymous = "ANONYMOUS"
  case authenticated = "AUTHENTICATED"
}

enum ApplicationInitializationResult {
  case success
  case settingsInitializationFailed(String)
  case secrecyChannelFailed(String)
  case deviceRegistrationFailed(String)
}

final class AppStateManager {

  static let shared: AppStateManager = AppStateManager()
  private let lock: NSLock = NSLock()
  private var _currentState: ApplicationState = .initializing
  private var _currentMembershipId: String?

  private init() {}
  var currentState: ApplicationState {
    lock.lock()
    defer { lock.unlock() }

    return _currentState
  }

  var currentMembershipId: String? {
    lock.lock()
    defer { lock.unlock() }

    return _currentMembershipId
  }

  func transitionToAnonymous() async {
    lock.withLock {
      _currentState = .anonymous
      _currentMembershipId = nil
    }
  }

  func transitionToAuthenticated(membershipId: String) async {
    guard !membershipId.isEmpty else {
      return
    }
    lock.withLock {
      _currentState = .authenticated
      _currentMembershipId = membershipId
    }
  }

  var isAuthenticated: Bool {
    currentState == .authenticated
  }

  var isAnonymous: Bool {
    currentState == .anonymous
  }

}

extension AppStateManager: ApplicationStateTransitioning {}
typealias ApplicationStateManager = AppStateManager
