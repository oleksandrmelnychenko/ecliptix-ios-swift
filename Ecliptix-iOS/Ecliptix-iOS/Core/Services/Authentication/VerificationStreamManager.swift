// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation

final class VerificationStreamManager {

  private let lock = NSLock()
  private var activeStreams: [String: UInt32] = [:]

  func tryGetActiveStream(_ sessionId: String) -> UInt32? {
    lock.lock()
    defer { lock.unlock() }

    return activeStreams[sessionId]
  }

  func registerStream(sessionId: String, connectId: UInt32) {
    lock.lock()
    defer { lock.unlock() }

    activeStreams[sessionId] = connectId
  }

  func processUpdate(sessionId: String, connectId: UInt32, status: OtpCountdownUpdate.Status) {
    lock.lock()
    defer { lock.unlock() }

    activeStreams[sessionId] = connectId
    if isTerminalStatus(status) {
      activeStreams.removeValue(forKey: sessionId)
    }
  }

  func closeStream(_ sessionId: String) {
    lock.lock()
    defer { lock.unlock() }

    activeStreams.removeValue(forKey: sessionId)
  }

  func closeAllStreams() {
    lock.lock()
    defer { lock.unlock() }

    activeStreams.removeAll()
  }

  private func isTerminalStatus(_ status: OtpCountdownUpdate.Status) -> Bool {
    switch status {
    case .otpCountdownStatusFailed,
      .otpCountdownStatusMaxAttemptsReached,
      .otpCountdownStatusNotFound,
      .otpCountdownStatusExpired,
      .otpCountdownStatusSessionExpired:
      return true
    default:
      return false
    }
  }
}
