// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum NetworkFailureType: Sendable {
  case dataCenterNotResponding
  case dataCenterShutdown
  case invalidRequestType
  case ecliptixProtocolFailure
  case protocolStateMismatch
  case sessionExpired
  case operationCancelled
  case criticalAuthenticationFailure
  case connectionFailed
  case masterKeySharesNotFound
  case kyberKeyRequired
  case rateLimited
}

struct NetworkFailure: Failure {

  let failureType: NetworkFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date
  let userError: UserFacingError?
  let requiresReinit: Bool

  init(
    failureType: NetworkFailureType,
    message: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil,
    requiresReinit: Bool = false
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
    self.userError = userError
    self.requiresReinit = requiresReinit
  }

  static func invalidRequestType(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .invalidRequestType,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func dataCenterNotResponding(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .dataCenterNotResponding,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func dataCenterShutdown(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .dataCenterShutdown,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func protocolStateMismatch(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .protocolStateMismatch,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func operationCancelled(
    _ details: String? = nil,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .operationCancelled,
      message: details ?? "Operation was cancelled",
      innerError: innerError,
      userError: userError
    )
  }

  static func criticalAuthenticationFailure(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .criticalAuthenticationFailure,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func connectionFailed(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .connectionFailed,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func ecliptixProtocolFailure(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .ecliptixProtocolFailure,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func sessionExpired(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .sessionExpired,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func masterKeySharesNotFound(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .masterKeySharesNotFound,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func kyberKeyRequired(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .kyberKeyRequired,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  static func rateLimited(
    _ details: String,
    innerError: Error? = nil,
    userError: UserFacingError? = nil
  ) -> NetworkFailure {
    NetworkFailure(
      failureType: .rateLimited,
      message: details,
      innerError: innerError,
      userError: userError
    )
  }

  func toStructuredLog() -> [String: Any] {
    var log: [String: Any] = [
      "failureType": String(describing: failureType),
      "message": message,
      "timestamp": timestamp.ISO8601Format(),
      "requiresReinit": requiresReinit,
    ]
    if let innerError = innerError {
      log["innerError"] = innerError.localizedDescription
    }
    if let userError = userError {
      log["userError"] = [
        "errorCode": userError.errorCode,
        "i18nKey": userError.i18nKey,
        "message": userError.message,
        "retryable": userError.retryable,
        "retryAfterMilliseconds": userError.retryAfterMilliseconds as Any,
        "correlationId": userError.correlationId as Any,
        "locale": userError.locale,
        "grpcStatusCode": userError.grpcStatusCode?.rawValue as Any,
      ]
    }
    return log
  }

  func toGrpcStatus() -> GRPCStatus {
    let descriptor = toGrpcDescriptor()
    return descriptor.createStatus(message)
  }

  func toGrpcDescriptor() -> GrpcErrorDescriptor {
    if let userError = userError {
      return GrpcErrorDescriptor(
        errorCode: userError.errorCode,
        statusCode: userError.grpcStatusCode ?? .internalError,
        i18nKey: userError.i18nKey,
        retryable: userError.retryable,
        retryAfterMilliseconds: userError.retryAfterMilliseconds
      )
    }
    switch failureType {
    case .dataCenterNotResponding:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.serviceUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.serviceUnavailable,
        retryable: true
      )
    case .dataCenterShutdown:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.serviceUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.serviceUnavailable
      )
    case .invalidRequestType:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    case .protocolStateMismatch:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .sessionExpired:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
      )
    case .operationCancelled:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.cancelled,
        statusCode: .cancelled,
        i18nKey: ErrorI18NKeys.cancelled
      )
    case .criticalAuthenticationFailure:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
      )
    case .ecliptixProtocolFailure:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    case .connectionFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.serviceUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.serviceUnavailable,
        retryable: true
      )
    case .masterKeySharesNotFound:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .kyberKeyRequired:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .rateLimited:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.resourceExhausted,
        statusCode: .resourceExhausted,
        i18nKey: ErrorI18NKeys.rateLimited,
        retryable: false
      )
    }
  }
}
