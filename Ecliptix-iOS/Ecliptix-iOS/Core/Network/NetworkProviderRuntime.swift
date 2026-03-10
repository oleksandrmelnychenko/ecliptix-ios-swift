// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class NetworkProviderInstanceSettingsStore: @unchecked Sendable {

  private let lock = NSLock()
  private var settings: NetworkProviderInstanceSettings?

  func set(_ settings: NetworkProviderInstanceSettings) {
    lock.withLock {
      self.settings = settings
    }
  }

  func update(_ mutate: (inout NetworkProviderInstanceSettings) -> Void) {
    lock.withLock {
      guard var current = settings else {
        return
      }
      mutate(&current)
      settings = current
    }
  }

  func current() -> NetworkProviderInstanceSettings? {
    lock.withLock { settings }
  }
}

final class NetworkProviderRequestRegistry: @unchecked Sendable {

  private let lock = NSLock()
  private var activeRequests: [String: CancellationToken] = [:]

  func contains(_ key: String) -> Bool {
    lock.withLock {
      activeRequests[key] != nil
    }
  }

  func register(_ key: String, token: CancellationToken) {
    lock.withLock {
      activeRequests[key] = token
    }
  }

  func unregister(_ key: String) {
    lock.withLock {
      activeRequests.removeValue(forKey: key)
    }
  }

  func cancelAll() {
    lock.withLock {
      for token in activeRequests.values {
        token.cancel()
      }
      activeRequests.removeAll()
    }
  }
}

final class NetworkProviderOutageState: @unchecked Sendable {

  private let outageLock = NSLock()
  private let pendingRetryLock = NSLock()
  private var isInOutage = false
  private var pendingRetryInProgress = false

  func currentOutageState() -> Bool {
    outageLock.withLock { isInOutage }
  }

  func enterOutage() {
    outageLock.withLock {
      isInOutage = true
    }
  }

  func exitOutage() {
    outageLock.withLock {
      isInOutage = false
    }
  }

  func beginPendingRetry() -> Bool {
    pendingRetryLock.withLock {
      if pendingRetryInProgress {
        return false
      }
      pendingRetryInProgress = true
      return true
    }
  }

  func finishPendingRetry() {
    pendingRetryLock.withLock {
      pendingRetryInProgress = false
    }
  }
}

final class NetworkProviderRuntime: @unchecked Sendable {

  let instanceSettingsStore: NetworkProviderInstanceSettingsStore
  let requestRegistry: NetworkProviderRequestRegistry
  let outageState: NetworkProviderOutageState
  let sessionRuntime: SecureSessionRuntime

  init(
    instanceSettingsStore: NetworkProviderInstanceSettingsStore =
      NetworkProviderInstanceSettingsStore(),
    requestRegistry: NetworkProviderRequestRegistry = NetworkProviderRequestRegistry(),
    outageState: NetworkProviderOutageState = NetworkProviderOutageState(),
    sessionRuntime: SecureSessionRuntime = SecureSessionRuntime()
  ) {
    self.instanceSettingsStore = instanceSettingsStore
    self.requestRegistry = requestRegistry
    self.outageState = outageState
    self.sessionRuntime = sessionRuntime
  }
}
