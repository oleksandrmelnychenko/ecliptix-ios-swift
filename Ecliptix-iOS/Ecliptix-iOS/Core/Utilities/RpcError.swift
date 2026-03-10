// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum RpcError: Sendable, CustomStringConvertible {
  case serverError(code: String, message: String)
  case grpcError(code: String, message: String)
  case serializationFailed(String)
  case deserializationFailed(String)
  case encryptionFailed(String)
  case decryptionFailed(String)
  case sessionNotFound
  case sessionRecoveryFailed(String)
  case unexpected(String)
  var serverErrorCode: String? {
    if case .serverError(let code, _) = self { return code }
    return nil
  }

  var isRetryable: Bool {
    switch self {
    case .decryptionFailed, .sessionNotFound, .sessionRecoveryFailed:
      return true
    case .grpcError(let code, let message):
      let lower = code.lowercased()
      return lower == "unavailable" || lower == "deadline_exceeded"
        || lower == "deadlineexceeded" || lower == "cancelled"
        || (lower == "unauthenticated"
          && message.lowercased().contains(ServerErrorCode.Session.reinitRequired))
    case .serverError(let code, _):
      return code == ServerErrorCode.Session.reinitRequired
    case .unexpected(let msg):
      let lower = msg.lowercased()
      return lower.contains("unavailable") || lower.contains("timeout")
        || lower.contains("connection") || lower.contains("eof")
        || lower.contains("broken pipe")
    case .serializationFailed, .deserializationFailed, .encryptionFailed:
      return false
    }
  }

  var requiresStateCleanup: Bool {
    switch self {
    case .decryptionFailed:
      return true
    case .grpcError(let code, let message):
      return code.lowercased() == "unauthenticated"
        && message.lowercased().contains(ServerErrorCode.Session.reinitRequired)
    case .serverError(let code, _):
      return code == ServerErrorCode.Session.reinitRequired
    default:
      return false
    }
  }

  var isTransient: Bool {
    switch self {
    case .grpcError(let code, let message):
      let lower = code.lowercased()
      return lower == "unavailable" || lower == "deadline_exceeded"
        || lower == "deadlineexceeded" || lower == "cancelled"
        || (lower == "unauthenticated"
          && message.lowercased().contains(ServerErrorCode.Session.reinitRequired))
    case .sessionNotFound, .sessionRecoveryFailed:
      return true
    case .decryptionFailed:
      return true
    case .serverError(let code, _):
      return code == ServerErrorCode.Session.reinitRequired
    case .unexpected(let msg):
      let lower = msg.lowercased()
      return lower.contains("unavailable") || lower.contains("timeout")
        || lower.contains("connection") || lower.contains("eof")
        || lower.contains("broken pipe") || lower.contains("session not found")
    case .serializationFailed, .deserializationFailed, .encryptionFailed:
      return false
    }
  }

  var userFacingMessage: String {
    switch self {
    case .serverError(let code, let message):
      let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, !ServerErrorMapper.prefersMappedMessage(for: code) { return trimmed }
      return ServerErrorMapper.mapServerErrorCode(code)
    case .grpcError:
      return String(localized: "Connection error. Please check your internet and try again.")
    case .serializationFailed, .deserializationFailed:
      return String(localized: "Something went wrong. Please try again.")
    case .encryptionFailed, .decryptionFailed:
      return String(localized: "Security error. Please try again.")
    case .sessionNotFound, .sessionRecoveryFailed:
      return String(localized: "Session expired. Please sign in again.")
    case .unexpected(let msg):
      return ServerErrorMapper.userFacingMessage(msg)
    }
  }

  var description: String { logDescription }
  var logDescription: String {
    switch self {
    case .serverError(let code, let message):
      return message.isEmpty ? "serverError[\(code)]" : "serverError[\(code)]: \(message)"
    case .grpcError(let code, let message):
      return "grpcError[\(code)]: \(message)"
    case .serializationFailed(let ctx):
      return "serializationFailed: \(ctx)"
    case .deserializationFailed(let ctx):
      return "deserializationFailed: \(ctx)"
    case .encryptionFailed(let detail):
      return "encryptionFailed: \(detail)"
    case .decryptionFailed(let detail):
      return "decryptionFailed: \(detail)"
    case .sessionNotFound:
      return "sessionNotFound"
    case .sessionRecoveryFailed(let detail):
      return "sessionRecoveryFailed: \(detail)"
    case .unexpected(let msg):
      return "unexpected: \(msg)"
    }
  }
}
