// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

@MainActor
final class CountdownTimer {

  private var task: Task<Void, Never>?

  var isRunning: Bool { task != nil && !(task?.isCancelled ?? true) }

  func start(
    seconds: Int,
    onTick: @escaping @MainActor (Int) -> Void,
    onFinish: @escaping @MainActor () -> Void
  ) {
    cancel()
    task = Task { [weak self] in
      defer { self?.task = nil }

      var remaining = seconds
      while remaining > 0 {
        do {
          try await Task.sleep(nanoseconds: 1_000_000_000)
        } catch {
          return
        }
        guard !Task.isCancelled else { return }
        remaining -= 1
        onTick(remaining)
      }
      guard !Task.isCancelled else { return }
      onFinish()
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
  }
}
