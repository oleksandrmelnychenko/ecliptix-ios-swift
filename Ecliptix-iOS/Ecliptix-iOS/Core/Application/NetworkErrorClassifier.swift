// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum NetworkErrorClassifier {

  private static let connectivityMarkers = [
    "no internet",
    "not connected",
    "connection",
    "timeout",
    "timed out",
    "network",
    "unreachable",
    "refused",
    "cannot reach server",
    "server unavailable",
    "offline",
  ]

  private static let secureRetryMarkers = [
    "unavailable",
    "deadlineexceeded",
    "deadline exceeded",
    "cancelled",
    "timeout",
    "timed out",
    "connection",
    "eof",
    "broken pipe",
    "secure session not found",
    "session not found",
    "failed to decrypt",
    ServerErrorCode.Session.reinitRequired,
  ]

  static func isConnectivityIssue(_ message: String) -> Bool {
    let normalized = message.lowercased()
    return connectivityMarkers.contains { normalized.contains($0) }
  }

  static func shouldRetrySecureUnary(_ message: String) -> Bool {
    let normalized = message.lowercased()
    return secureRetryMarkers.contains { normalized.contains($0) }
  }

  static func shouldRetrySecureUnary(_ error: RpcError) -> Bool {
    error.isRetryable
  }

  static func isConnectivityIssue(_ error: RpcError) -> Bool {
    switch error {
    case .grpcError, .sessionNotFound, .sessionRecoveryFailed:
      return true
    case .serverError(let code, _):
      return code == ServerErrorCode.Streaming.unavailable
        || code == ServerErrorCode.Messaging.chatUnavailable
    case .unexpected(let msg):
      return isConnectivityIssue(msg)
    default:
      return false
    }
  }
}
