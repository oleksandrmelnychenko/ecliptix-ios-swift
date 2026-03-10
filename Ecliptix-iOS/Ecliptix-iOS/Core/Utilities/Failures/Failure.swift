// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct GRPCStatus {

  enum Code: Int {
    case ok = 0
    case cancelled = 1
    case unknown = 2
    case invalidArgument = 3
    case deadlineExceeded = 4
    case notFound = 5
    case alreadyExists = 6
    case permissionDenied = 7
    case resourceExhausted = 8
    case failedPrecondition = 9
    case aborted = 10
    case outOfRange = 11
    case unimplemented = 12
    case internalError = 13
    case unavailable = 14
    case dataLoss = 15
    case unauthenticated = 16
    static var `internal`: Code { .internalError }
  }

  let code: Code
  let message: String?
  var isOk: Bool {
    code == .ok
  }

  init(code: Code, message: String? = nil) {
    self.code = code
    self.message = message
  }
}

protocol Failure {

  var message: String { get }
  var innerError: Error? { get }
  var timestamp: Date { get }

  func toStructuredLog() -> [String: Any]

  func toGrpcStatus() -> GRPCStatus
}

struct FailureBase: Failure {

  let message: String
  let innerError: Error?
  let timestamp: Date

  init(message: String, innerError: Error? = nil) {
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  func toStructuredLog() -> [String: Any] {
    var log: [String: Any] = [
      "message": message,
      "timestamp": timestamp.ISO8601Format(),
    ]
    if let innerError = innerError {
      log["innerError"] = innerError.localizedDescription
    }
    return log
  }

  func toGrpcStatus() -> GRPCStatus {
    GRPCStatus(code: .internal, message: message)
  }
}

struct UserFacingError {

  let errorCode: String
  let i18nKey: String
  let message: String
  let retryable: Bool
  let retryAfterMilliseconds: Int?
  let correlationId: String?
  let locale: String
  let grpcStatusCode: GRPCStatus.Code?

  init(
    errorCode: String,
    i18nKey: String,
    message: String,
    retryable: Bool = false,
    retryAfterMilliseconds: Int? = nil,
    correlationId: String? = nil,
    locale: String = Locale.current.identifier,
    grpcStatusCode: GRPCStatus.Code? = nil
  ) {
    self.errorCode = errorCode
    self.i18nKey = i18nKey
    self.message = message
    self.retryable = retryable
    self.retryAfterMilliseconds = retryAfterMilliseconds
    self.correlationId = correlationId
    self.locale = locale
    self.grpcStatusCode = grpcStatusCode
  }
}

struct GrpcErrorDescriptor {

  let errorCode: String
  let statusCode: GRPCStatus.Code
  let i18nKey: String
  let retryable: Bool
  let retryAfterMilliseconds: Int?

  init(
    errorCode: String,
    statusCode: GRPCStatus.Code,
    i18nKey: String,
    retryable: Bool = false,
    retryAfterMilliseconds: Int? = nil
  ) {
    self.errorCode = errorCode
    self.statusCode = statusCode
    self.i18nKey = i18nKey
    self.retryable = retryable
    self.retryAfterMilliseconds = retryAfterMilliseconds
  }

  func createStatus(_ message: String) -> GRPCStatus {
    GRPCStatus(code: statusCode, message: message)
  }
}

enum ErrorCode {

  static let serviceUnavailable = "SERVICE_UNAVAILABLE"
  static let validationFailed = "VALIDATION_FAILED"
  static let internalError = "INTERNAL_ERROR"
  static let preconditionFailed = "PRECONDITION_FAILED"
  static let unauthenticated = "UNAUTHENTICATED"
  static let cancelled = "CANCELLED"
  static let maxAttemptsReached = "MAX_ATTEMPTS_REACHED"
  static let notFound = "NOT_FOUND"
  static let resourceExhausted = "RESOURCE_EXHAUSTED"
  static let dependencyUnavailable = "DEPENDENCY_UNAVAILABLE"
}

enum ErrorI18NKeys {

  static let serviceUnavailable = "error.service_unavailable"
  static let validation = "error.validation"
  static let `internal` = "error.internal"
  static let preconditionFailed = "error.precondition_failed"
  static let unauthenticated = "error.unauthenticated"
  static let cancelled = "error.cancelled"
  static let maxAttempts = "error.max_attempts"
  static let notFound = "error.not_found"
  static let resourceExhausted = "error.resource_exhausted"
  static let dependencyUnavailable = "error.dependency_unavailable"
  static let rateLimited = "error.rate_limited"
  static let mobileNumberRequired = "error.auth.mobile_number_required"
  static let secureKeyRequired = "error.auth.secure_key_required"
  static let invalidCredentials = "error.auth.invalid_credentials"
  static let loginAttemptExceeded = "error.auth.login_attempt_exceeded"
  static let keyExchangeUnavailable = "error.auth.key_exchange_unavailable"
  static let membershipMissing = "error.auth.membership_missing"
  static let invalidMembershipId = "error.auth.invalid_membership_id"
  static let invalidAccountId = "error.auth.invalid_account_id"
  static let opaqueOperationFailed = "error.auth.opaque_operation_failed"
  static let registrationRequired = "error.auth.registration_required"
  static let registrationInProgress = "error.registration.in_progress"
  static let membershipIdRequired = "error.registration.membership_id_required"
  static let registrationRequestUnavailable = "error.registration.request_unavailable"
  static let registrationInitFailed = "error.registration.init_failed"
  static let registrationCompleteFailed = "error.registration.complete_failed"
  static let mobileValidationEmpty = "error.registration.mobile_validation_empty"
  static let mobileAlreadyRegistered = "error.registration.mobile_already_registered"
  static let mobileDataCorrupted = "error.registration.mobile_data_corrupted"
  static let mobileNotAvailable = "error.registration.mobile_not_available"
  static let recoveryInProgress = "error.recovery.in_progress"
  static let recoveryRequestUnavailable = "error.recovery.request_unavailable"
  static let recoveryInitFailed = "error.recovery.init_failed"
  static let pinRegisterFailed = "error.pin.register_failed"
  static let pinVerifyFailed = "error.pin.verify_failed"
  static let pinAccountNotFound = "error.pin.account_not_found"
  static let pinLocked = "error.pin.locked"
  static let pinNotRegistered = "error.pin.not_registered"
  static let pinInvalidLength = "error.pin.invalid_length"
}

enum PinOpaqueFailure: Error {
  case invalidPinLength(String)
  case accountNotFound(String)
  case notRegistered(String)
  case locked(remaining: UInt32, message: String)
  case attemptsExceeded(remaining: UInt32, message: String)
  case invalidPin(remaining: UInt32, message: String)
  case networkFailed(RpcError)
  case cryptoFailed(String)
  case unexpectedError(String)
  var message: String {
    switch self {
    case .invalidPinLength(let msg), .accountNotFound(let msg),
      .notRegistered(let msg),
      .cryptoFailed(let msg), .unexpectedError(let msg):
      return msg
    case .networkFailed(let err):
      return err.logDescription
    case .locked(_, let msg), .attemptsExceeded(_, let msg),
      .invalidPin(_, let msg):
      return msg
    }
  }
}
