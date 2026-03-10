// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum ValidationFailureType {
  case signInFailed
  case loginAttemptExceeded
}

struct ValidationFailure: Failure {

  let failureType: ValidationFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: ValidationFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func signInFailed(_ details: String, innerError: Error? = nil) -> ValidationFailure {
    ValidationFailure(failureType: .signInFailed, message: details, innerError: innerError)
  }

  static func loginAttemptExceeded(_ details: String, innerError: Error? = nil)
    -> ValidationFailure
  {
    ValidationFailure(
      failureType: .loginAttemptExceeded, message: details, innerError: innerError)
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
    case .loginAttemptExceeded:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.maxAttemptsReached,
        statusCode: .resourceExhausted,
        i18nKey: ErrorI18NKeys.maxAttempts
      )
    case .signInFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    }
  }
}
