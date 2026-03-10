// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum CryptographyFailureType {
  case initializationFailed
  case libraryNotFound
  case allocationFailed
  case memoryPinningFailed
  case secureWipeFailed
  case invalidBufferSize
  case bufferTooSmall
  case bufferTooLarge
  case nullPointer
  case memoryProtectionFailed
  case comparisonFailed
}

struct CryptographyFailure: Failure, Error {

  let failureType: CryptographyFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: CryptographyFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func initializationFailed(_ details: String, innerError: Error? = nil)
    -> CryptographyFailure
  {
    CryptographyFailure(
      failureType: .initializationFailed, message: details, innerError: innerError)
  }

  static func comparisonFailed(_ details: String, innerError: Error? = nil) -> CryptographyFailure {
    CryptographyFailure(
      failureType: .comparisonFailed, message: details, innerError: innerError)
  }

  static func libraryNotFound(_ details: String, innerError: Error? = nil) -> CryptographyFailure {
    CryptographyFailure(failureType: .libraryNotFound, message: details, innerError: innerError)
  }

  static func allocationFailed(_ details: String, innerError: Error? = nil) -> CryptographyFailure {
    CryptographyFailure(
      failureType: .allocationFailed, message: details, innerError: innerError)
  }

  static func memoryPinningFailed(_ details: String, innerError: Error? = nil)
    -> CryptographyFailure
  {
    CryptographyFailure(
      failureType: .memoryPinningFailed, message: details, innerError: innerError)
  }

  static func secureWipeFailed(_ details: String, innerError: Error? = nil) -> CryptographyFailure {
    CryptographyFailure(
      failureType: .secureWipeFailed, message: details, innerError: innerError)
  }

  static func memoryProtectionFailed(_ details: String, innerError: Error? = nil)
    -> CryptographyFailure
  {
    CryptographyFailure(
      failureType: .memoryProtectionFailed, message: details, innerError: innerError)
  }

  static func nullPointer(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .nullPointer, message: details)
  }

  static func invalidBufferSize(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .invalidBufferSize, message: details)
  }

  static func bufferTooSmall(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .bufferTooSmall, message: details)
  }

  static func bufferTooLarge(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .bufferTooLarge, message: details)
  }

  static func invalidOperation(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .invalidBufferSize, message: details)
  }

  static func objectDisposed(_ details: String) -> CryptographyFailure {
    CryptographyFailure(failureType: .nullPointer, message: details)
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
    case .initializationFailed, .memoryPinningFailed, .secureWipeFailed,
      .nullPointer, .memoryProtectionFailed, .comparisonFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    case .libraryNotFound:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.dependencyUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.dependencyUnavailable
      )
    case .allocationFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.resourceExhausted,
        statusCode: .resourceExhausted,
        i18nKey: ErrorI18NKeys.resourceExhausted
      )
    case .invalidBufferSize, .bufferTooSmall, .bufferTooLarge:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    }
  }
}
