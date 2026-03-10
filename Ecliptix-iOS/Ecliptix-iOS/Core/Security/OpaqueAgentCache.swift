// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class OpaqueAgentCache: @unchecked Sendable {

  private let lock = NSLock()
  private var cachedAgent: OpaqueAgent?
  private var cachedServerPublicKey: Data?

  func getOrCreateAgent(serverPublicKey: Data) throws -> OpaqueAgent {
    lock.lock()
    defer { lock.unlock() }

    if let agent = cachedAgent, cachedServerPublicKey == serverPublicKey {
      return agent
    }
    cachedAgent?.dispose()
    let agent = try OpaqueAgent(serverPublicKey: serverPublicKey)
    cachedAgent = agent
    cachedServerPublicKey = serverPublicKey
    return agent
  }

  func invalidate() {
    lock.lock()
    defer { lock.unlock() }

    cachedAgent?.dispose()
    cachedAgent = nil
    cachedServerPublicKey = nil
  }

  deinit {
    invalidate()
  }
}
