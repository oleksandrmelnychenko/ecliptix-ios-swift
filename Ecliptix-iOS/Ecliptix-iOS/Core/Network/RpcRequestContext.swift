// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct RpcRequestContext: Sendable {

  let requestId: UUID
  private(set) var attemptNumber: Int
  private(set) var reinitAttempted: Bool

  private init(requestId: UUID) {
    self.requestId = requestId
    self.attemptNumber = 1
    self.reinitAttempted = false
  }

  static func createNew() -> RpcRequestContext {
    RpcRequestContext(requestId: UUID())
  }

  mutating func incrementAttempt() {
    attemptNumber += 1
  }

  mutating func markReinitAttempted() {
    reinitAttempted = true
  }
}
