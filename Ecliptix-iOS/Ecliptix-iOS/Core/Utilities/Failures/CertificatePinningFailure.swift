// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum CertificatePinningFailureType {
  case serviceNotInitialized
  case serviceDisposed
  case libraryInitializationFailed
  case initializationException
  case certificateDataRequired
  case hostnameRequired
  case certificateValidationFailed
  case certificateValidationException
  case plaintextRequired
  case rsaEncryptionFailed
  case rsaEncryptionException
  case ciphertextRequired
  case rsaDecryptionFailed
  case rsaDecryptionException
  case messageRequired
  case invalidSignatureSize
  case ed25519VerificationError
  case ed25519VerificationException
  case serviceInitializing
  case serviceInvalidState
}

struct CertificatePinningFailure: Failure {

  let failureType: CertificatePinningFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: CertificatePinningFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func serviceNotInitialized() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .serviceNotInitialized,
      message: "Certificate pinning service not initialized"
    )
  }

  static func serviceDisposed() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .serviceDisposed,
      message: "Certificate pinning service disposed"
    )
  }

  static func libraryInitializationFailed(_ details: String) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .libraryInitializationFailed,
      message: "Library initialization failed: \(details)"
    )
  }

  static func initializationExceptionOccurred(_ error: Error) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .initializationException,
      message: "Initialization exception: \(error.localizedDescription)",
      innerError: error
    )
  }

  static func certificateValidationFailed(_ details: String) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .certificateValidationFailed,
      message: "Certificate validation failed: \(details)"
    )
  }

  static func certificateValidationExceptionOccurred(_ error: Error) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .certificateValidationException,
      message: "Certificate validation exception: \(error.localizedDescription)",
      innerError: error
    )
  }

  static func plaintextRequired() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .plaintextRequired,
      message: "Plaintext required"
    )
  }

  static func rsaEncryptionFailed(_ details: String) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .rsaEncryptionFailed,
      message: "RSA encryption failed: \(details)"
    )
  }

  static func rsaEncryptionExceptionOccurred(_ error: Error) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .rsaEncryptionException,
      message: "RSA encryption exception: \(error.localizedDescription)",
      innerError: error
    )
  }

  static func ciphertextRequired() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .ciphertextRequired,
      message: "Ciphertext required"
    )
  }

  static func rsaDecryptionFailed(_ details: String) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .rsaDecryptionFailed,
      message: "RSA decryption failed: \(details)"
    )
  }

  static func rsaDecryptionExceptionOccurred(_ error: Error) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .rsaDecryptionException,
      message: "RSA decryption exception: \(error.localizedDescription)",
      innerError: error
    )
  }

  static func messageRequired() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .messageRequired,
      message: "Message required"
    )
  }

  static func invalidSignatureSize(_ expectedSize: Int) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .invalidSignatureSize,
      message: "Signature must be \(expectedSize) bytes"
    )
  }

  static func ed25519VerificationError(_ details: String) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .ed25519VerificationError,
      message: "Ed25519 verification error: \(details)"
    )
  }

  static func ed25519VerificationExceptionOccurred(_ error: Error) -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .ed25519VerificationException,
      message: "Ed25519 verification exception: \(error.localizedDescription)",
      innerError: error
    )
  }

  static func serviceInitializing() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .serviceInitializing,
      message: "Service initializing"
    )
  }

  static func serviceInvalidState() -> CertificatePinningFailure {
    CertificatePinningFailure(
      failureType: .serviceInvalidState,
      message: "Service invalid state"
    )
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
    case .serviceNotInitialized, .serviceDisposed, .serviceInitializing, .serviceInvalidState:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .libraryInitializationFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.dependencyUnavailable,
        statusCode: .unavailable,
        i18nKey: ErrorI18NKeys.dependencyUnavailable
      )
    case .certificateDataRequired, .hostnameRequired, .plaintextRequired,
      .ciphertextRequired, .messageRequired, .invalidSignatureSize:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    case .certificateValidationFailed, .ed25519VerificationError:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
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
