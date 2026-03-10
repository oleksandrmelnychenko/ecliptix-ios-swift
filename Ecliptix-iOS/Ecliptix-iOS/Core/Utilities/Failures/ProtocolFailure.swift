// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum ProtocolFailureType {
  case generic
  case decodeFailed
  case deriveKeyFailed
  case handshakeFailed
  case peerPubKeyFailed
  case invalidInput
  case objectDisposed
  case allocationFailed
  case pinningFailure
  case bufferTooSmall
  case dataTooLarge
  case keyGenerationFailed
  case prepareLocalFailed
  case memoryBufferError
  case stateMismatch
  case sessionExpired
  case groupProtocol
  case groupMembership
  case treeIntegrity
  case welcome
  case messageExpired
  case franking
}

struct ProtocolFailure: Failure {

  let failureType: ProtocolFailureType
  let message: String
  let innerError: Error?
  let timestamp: Date

  init(
    failureType: ProtocolFailureType,
    message: String,
    innerError: Error? = nil
  ) {
    self.failureType = failureType
    self.message = message
    self.innerError = innerError
    self.timestamp = Date()
  }

  static func generic(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .generic, message: details, innerError: innerError)
  }

  static func decode(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .decodeFailed, message: details, innerError: innerError)
  }

  static func deriveKey(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .deriveKeyFailed, message: details, innerError: innerError)
  }

  static func handshake(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .handshakeFailed, message: details, innerError: innerError)
  }

  static func peerPubKey(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .peerPubKeyFailed, message: details, innerError: innerError)
  }

  static func invalidInput(_ details: String) -> ProtocolFailure {
    ProtocolFailure(failureType: .invalidInput, message: details)
  }

  static func objectDisposed(_ resourceName: String) -> ProtocolFailure {
    ProtocolFailure(
      failureType: .objectDisposed,
      message: "Cannot access disposed resource '\(resourceName)'")
  }

  static func allocationFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .allocationFailed, message: details, innerError: innerError)
  }

  static func pinningFailure(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .pinningFailure, message: details, innerError: innerError)
  }

  static func bufferTooSmall(_ details: String) -> ProtocolFailure {
    ProtocolFailure(failureType: .bufferTooSmall, message: details)
  }

  static func dataTooLarge(_ details: String) -> ProtocolFailure {
    ProtocolFailure(failureType: .dataTooLarge, message: details)
  }

  static func keyGeneration(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .keyGenerationFailed, message: details, innerError: innerError)
  }

  static func prepareLocal(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .prepareLocalFailed, message: details, innerError: innerError)
  }

  static func memoryBufferError(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .memoryBufferError, message: details, innerError: innerError)
  }

  static func stateMismatch(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .stateMismatch, message: details, innerError: innerError)
  }

  static func sessionExpired(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .sessionExpired, message: details, innerError: innerError)
  }

  static func keyGenerationFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    keyGeneration(details, innerError: innerError)
  }

  static func keyDerivationFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    deriveKey(details, innerError: innerError)
  }

  static func handshakeFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    handshake(details, innerError: innerError)
  }

  static func encryptionFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    generic(details, innerError: innerError)
  }

  static func decryptionFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    generic(details, innerError: innerError)
  }

  static func protocolStateMismatch(_ details: String, innerError: Error? = nil)
    -> ProtocolFailure
  {
    stateMismatch(details, innerError: innerError)
  }

  static func bufferSizeMismatch(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    bufferTooSmall(details)
  }

  static func memoryAllocationFailed(_ details: String, innerError: Error? = nil)
    -> ProtocolFailure
  {
    allocationFailed(details, innerError: innerError)
  }

  static func cryptographicOperationFailed(_ details: String, innerError: Error? = nil)
    -> ProtocolFailure
  {
    generic(details, innerError: innerError)
  }

  static func replayAttackDetected(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    stateMismatch(details, innerError: innerError)
  }

  static func postQuantumKeyMissing(_ details: String, innerError: Error? = nil)
    -> ProtocolFailure
  {
    invalidInput(details)
  }

  static func groupProtocolFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .groupProtocol, message: details, innerError: innerError)
  }

  static func groupMembershipFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure
  {
    ProtocolFailure(failureType: .groupMembership, message: details, innerError: innerError)
  }

  static func treeIntegrityFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .treeIntegrity, message: details, innerError: innerError)
  }

  static func welcomeFailed(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    ProtocolFailure(failureType: .welcome, message: details, innerError: innerError)
  }

  static func messageExpiredFailure(_ details: String, innerError: Error? = nil) -> ProtocolFailure
  {
    ProtocolFailure(failureType: .messageExpired, message: details, innerError: innerError)
  }

  static func frankingVerificationFailed(_ details: String, innerError: Error? = nil)
    -> ProtocolFailure
  {
    ProtocolFailure(failureType: .franking, message: details, innerError: innerError)
  }

  static func unexpectedError(_ details: String, innerError: Error? = nil) -> ProtocolFailure {
    generic(details, innerError: innerError)
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
    case .sessionExpired:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.unauthenticated,
        statusCode: .unauthenticated,
        i18nKey: ErrorI18NKeys.unauthenticated
      )
    case .stateMismatch, .handshakeFailed, .peerPubKeyFailed, .prepareLocalFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.preconditionFailed,
        statusCode: .failedPrecondition,
        i18nKey: ErrorI18NKeys.preconditionFailed
      )
    case .invalidInput, .bufferTooSmall, .dataTooLarge:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.validationFailed,
        statusCode: .invalidArgument,
        i18nKey: ErrorI18NKeys.validation
      )
    case .allocationFailed:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.resourceExhausted,
        statusCode: .resourceExhausted,
        i18nKey: ErrorI18NKeys.resourceExhausted
      )
    default:
      return GrpcErrorDescriptor(
        errorCode: ErrorCode.internalError,
        statusCode: .internalError,
        i18nKey: ErrorI18NKeys.internal
      )
    }
  }

  func toNetworkFailure() -> NetworkFailure {
    let networkFailureType: NetworkFailureType
    switch failureType {
    case .stateMismatch:
      networkFailureType = .protocolStateMismatch
    case .sessionExpired:
      networkFailureType = .sessionExpired
    default:
      networkFailureType = .ecliptixProtocolFailure
    }
    return NetworkFailure(
      failureType: networkFailureType,
      message: message,
      innerError: innerError
    )
  }
}
