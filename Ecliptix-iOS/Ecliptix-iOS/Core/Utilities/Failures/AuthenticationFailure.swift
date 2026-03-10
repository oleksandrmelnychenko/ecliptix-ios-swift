// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum AuthenticationFailureType {
  case invalidCredentials
  case loginAttemptExceeded
  case mobileNumberRequired
  case secureKeyRequired
  case unexpectedError
  case secureMemoryAllocationFailed
  case secureMemoryWriteFailed
  case keyDerivationFailed
  case masterKeyDerivationFailed
  case networkRequestFailed
  case invalidMembershipId
  case identityStorageFailed
  case criticalAuthenticationError
  case keychainCorrupted
  case registrationRequired
}

struct AuthenticationFailure: Failure {

  let failureType: AuthenticationFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: AuthenticationFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func invalidCredentials(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .invalidCredentials, message: details, innerError: innerError)
  }

  static func loginAttemptExceeded(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .loginAttemptExceeded, message: details, innerError: innerError)
  }

  static func mobileNumberRequired(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .mobileNumberRequired, message: details, innerError: innerError)
  }

  static func secureKeyRequired(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .secureKeyRequired, message: details, innerError: innerError)
  }

  static func unexpectedError(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .unexpectedError, message: details, innerError: innerError)
  }

  static func secureMemoryAllocationFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .secureMemoryAllocationFailed, message: details, innerError: innerError)
  }

  static func secureMemoryWriteFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .secureMemoryWriteFailed, message: details, innerError: innerError)
  }

  static func keyDerivationFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .keyDerivationFailed, message: details, innerError: innerError)
  }

  static func masterKeyDerivationFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .masterKeyDerivationFailed, message: details, innerError: innerError)
  }

  static func networkRequestFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .networkRequestFailed, message: details, innerError: innerError)
  }

  static func invalidMembershipIdentifier(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .invalidMembershipId, message: details, innerError: innerError)
  }

  static func identityStorageFailed(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .identityStorageFailed, message: details, innerError: innerError)
  }

  static func criticalAuthenticationError(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .criticalAuthenticationError, message: details, innerError: innerError)
  }

  static func keychainCorrupted(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .keychainCorrupted, message: details, innerError: innerError)
  }

  static func registrationRequired(_ details: String, innerError: Error? = nil)
    -> AuthenticationFailure
  {
    AuthenticationFailure(
      failureType: .registrationRequired, message: details, innerError: innerError)
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
    case .invalidCredentials:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
      )
    case .loginAttemptExceeded:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.maxAttemptsReached,
        statusCode: .resourceExhausted,
        i18nKey: ErrorI18NKeys.maxAttempts
      )
    case .mobileNumberRequired, .secureKeyRequired:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    case .networkRequestFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.serviceUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.serviceUnavailable,
        retryable: true
      )
    case .invalidMembershipId:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.notFound,
        statusCode: .notFound,
        i18nKey: ErrorI18NKeys.notFound
      )
    case .criticalAuthenticationError:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
      )
    case .registrationRequired:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.notFound,
        statusCode: .notFound,
        i18nKey: ErrorI18NKeys.registrationRequired
      )
    default:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    }
  }
}
