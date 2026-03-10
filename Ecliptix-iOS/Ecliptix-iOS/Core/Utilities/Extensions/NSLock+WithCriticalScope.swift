// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension NSLock {

  @inlinable
  func withCriticalScope<T>(_ body: () throws -> T) rethrows -> T {
    lock()
    defer { unlock() }

    return try body()
  }
}
