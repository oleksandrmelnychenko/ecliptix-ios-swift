// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum TransientErrorDetection {

  private static let transientMarkers = [
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
  ]

  static func isTransient(_ errorMessage: String) -> Bool {
    let normalized = errorMessage.lowercased()
    return transientMarkers.contains { normalized.contains($0) }
  }

  static func isTransient(_ failure: NetworkFailure) -> Bool {
    switch failure.failureType {
    case .dataCenterNotResponding, .operationCancelled, .connectionFailed:
      return true
    case .sessionExpired, .protocolStateMismatch, .criticalAuthenticationFailure,
      .invalidRequestType, .ecliptixProtocolFailure,
      .masterKeySharesNotFound, .kyberKeyRequired, .dataCenterShutdown, .rateLimited:
      return false
    }
  }

  static func isTransient(_ error: RpcError) -> Bool {
    error.isTransient
  }

  static func computeExponentialDelay(
    attempt: Int,
    initialDelay: TimeInterval = 0.5,
    maxDelay: TimeInterval = 2.0
  ) -> TimeInterval {
    let exponentialDelay = initialDelay * pow(2.0, Double(attempt - 1))
    return min(exponentialDelay, maxDelay)
  }

  static func executeWithRetry<T>(
    maxAttempts: Int = 3,
    operation: () async -> Result<T, String>
  ) async -> Result<T, String> {
    var lastError = "Unknown error"
    for attempt in 1...maxAttempts {
      let result = await operation()
      if result.isOk { return result }
      lastError = result.err() ?? "Unknown error"
      guard attempt < maxAttempts, isTransient(lastError) else { break }
      let delay = computeExponentialDelay(attempt: attempt)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    return .err(lastError)
  }

  static func executeWithRetry<T>(
    maxAttempts: Int = 3,
    operation: () async -> Result<T, RpcError>
  ) async -> Result<T, RpcError> {
    var lastError: RpcError = .unexpected("Unknown error")
    for attempt in 1...maxAttempts {
      let result = await operation()
      if result.isOk { return result }
      lastError = result.unwrapErr()
      guard attempt < maxAttempts, lastError.isTransient else { break }
      let delay = computeExponentialDelay(attempt: attempt)
      try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
    return .err(lastError)
  }
}
