// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum LogoutFailureType {
  case networkRequestFailed
  case alreadyLoggedOut
  case sessionNotFound
  case invalidMembershipIdentifier
  case cryptographicOperationFailed
  case invalidRevocationProof
  case unexpectedError
}

struct LogoutFailure: Failure {

  let failureType: LogoutFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: LogoutFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func networkRequestFailed(_ details: String, innerError: Error? = nil) -> LogoutFailure {
    LogoutFailure(failureType: .networkRequestFailed, message: details, innerError: innerError)
  }

  static func alreadyLoggedOut(_ details: String, innerError: Error? = nil) -> LogoutFailure {
    LogoutFailure(failureType: .alreadyLoggedOut, message: details, innerError: innerError)
  }

  static func sessionNotFound(_ details: String, innerError: Error? = nil) -> LogoutFailure {
    LogoutFailure(failureType: .sessionNotFound, message: details, innerError: innerError)
  }

  static func invalidMembershipIdentifier(_ details: String, innerError: Error? = nil)
    -> LogoutFailure
  {
    LogoutFailure(
      failureType: .invalidMembershipIdentifier, message: details, innerError: innerError)
  }

  static func cryptographicOperationFailed(_ details: String, innerError: Error? = nil)
    -> LogoutFailure
  {
    LogoutFailure(
      failureType: .cryptographicOperationFailed, message: details, innerError: innerError)
  }

  static func invalidRevocationProof(_ details: String, innerError: Error? = nil) -> LogoutFailure {
    LogoutFailure(failureType: .invalidRevocationProof, message: details, innerError: innerError)
  }

  static func unexpectedError(_ details: String, innerError: Error? = nil) -> LogoutFailure {
    LogoutFailure(failureType: .unexpectedError, message: details, innerError: innerError)
  }

  func toStructuredLog() -> [String: Any] {
    var log: [String: Any] = [
      "failureType": String(describing: failureType),
      "message": message,
      "timestamp": timestamp.ISO8601Format(),
    ]
    if let innerError = innerError {
      log["innerError"] = innerError.localizedDescription
    }
    return log
  }

  func toGrpcStatus() -> GRPCStatus {
    let descriptor = toGrpcDescriptor()
    return descriptor.createStatus(message)
  }

  func toGrpcDescriptor() -> GrpcErrorDescriptor {
    switch failureType {
    case .networkRequestFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.serviceUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.serviceUnavailable,
        retryable: true
      )
    case .alreadyLoggedOut:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .sessionNotFound:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.notFound,
        statusCode: .notFound,
        i18nKey: ErrorI18NKeys.notFound
      )
    case .invalidMembershipIdentifier:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .cryptographicOperationFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    case .invalidRevocationProof:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    case .unexpectedError:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    }
  }
}
