// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

enum OpaqueNative {

  static let PUBLIC_KEY_LENGTH: Int = 32
  static let REGISTRATION_REQUEST_LENGTH: Int = 33
  static let REGISTRATION_RESPONSE_LENGTH: Int = 65
  static let REGISTRATION_RECORD_LENGTH: Int = 169
  static let KE1_LENGTH: Int = 1273
  static let KE2_LENGTH: Int = 1377
  static let KE3_LENGTH: Int = 65
  static let SESSION_KEY_LENGTH: Int = 64
  static let MASTER_KEY_LENGTH: Int = 32

  typealias OpaqueClientHandle = OpaquePointer
  typealias RegistrationStateHandle = OpaquePointer
  typealias KeyExchangeStateHandle = OpaquePointer

  // Mirrors: typedef struct OpaqueError { OpaqueErrorCode code; char* message; } OpaqueError;
  struct OpaqueNativeError {

    var code: Int32
    var message: UnsafeMutablePointer<CChar>?
  }

  private static let _initialized = Mutex(false)

  @_silgen_name("opaque_init")
  private static func opaqueInit() -> Int32

  @_silgen_name("opaque_shutdown")
  private static func opaqueShutdown()

  @_silgen_name("opaque_error_free")
  private static func opaqueErrorFree(_ error: UnsafeMutablePointer<OpaqueNativeError>?)

  @_silgen_name("opaque_get_ke1_length")
  private static func opaqueGetKe1Length() -> Int

  @_silgen_name("opaque_get_ke2_length")
  private static func opaqueGetKe2Length() -> Int

  @_silgen_name("opaque_get_ke3_length")
  private static func opaqueGetKe3Length() -> Int

  @_silgen_name("opaque_get_registration_record_length")
  private static func opaqueGetRegistrationRecordLength() -> Int

  @_silgen_name("opaque_agent_create")
  private static func opaqueClientCreate(
    _ serverPublicKey: UnsafePointer<UInt8>,
    _ keyLength: Int,
    _ outHandle: UnsafeMutablePointer<OpaquePointer?>,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_destroy")
  private static func opaqueClientDestroy(_ handlePtr: UnsafeMutablePointer<OpaquePointer?>?)

  @_silgen_name("opaque_agent_state_create")
  private static func opaqueClientStateCreate(
    _ outHandle: UnsafeMutablePointer<OpaquePointer?>,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_state_destroy")
  private static func opaqueClientStateDestroy(_ handlePtr: UnsafeMutablePointer<OpaquePointer?>?)

  @_silgen_name("opaque_agent_create_registration_request")
  private static func opaqueClientCreateRegistrationRequest(
    _ clientHandle: OpaquePointer,
    _ password: UnsafePointer<UInt8>,
    _ passwordLen: Int,
    _ stateHandle: OpaquePointer,
    _ outRequest: UnsafeMutablePointer<UInt8>,
    _ outRequestLen: Int,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_finalize_registration")
  private static func opaqueClientFinalizeRegistration(
    _ clientHandle: OpaquePointer,
    _ response: UnsafePointer<UInt8>,
    _ responseLen: Int,
    _ stateHandle: OpaquePointer,
    _ outRecord: UnsafeMutablePointer<UInt8>,
    _ outRecordLen: Int,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_generate_ke1")
  private static func opaqueClientGenerateKe1(
    _ clientHandle: OpaquePointer,
    _ password: UnsafePointer<UInt8>,
    _ passwordLen: Int,
    _ stateHandle: OpaquePointer,
    _ outKe1: UnsafeMutablePointer<UInt8>,
    _ outKe1Len: Int,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_generate_ke3")
  private static func opaqueClientGenerateKe3(
    _ clientHandle: OpaquePointer,
    _ ke2: UnsafePointer<UInt8>,
    _ ke2Len: Int,
    _ stateHandle: OpaquePointer,
    _ outKe3: UnsafeMutablePointer<UInt8>,
    _ outKe3Len: Int,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  @_silgen_name("opaque_agent_finish")
  private static func opaqueClientFinish(
    _ clientHandle: OpaquePointer,
    _ stateHandle: OpaquePointer,
    _ outSessionKey: UnsafeMutablePointer<UInt8>,
    _ outSessionKeyLen: Int,
    _ outMasterKey: UnsafeMutablePointer<UInt8>,
    _ outMasterKeyLen: Int,
    _ outError: UnsafeMutablePointer<OpaqueNativeError>?
  ) -> Int32

  static func initialize() throws {
    try _initialized.withLock { initialized in
      guard !initialized else { return }
      let result = opaqueInit()
      guard result == ResultCode.success.rawValue else {
        throw OpaqueError.cryptoError(
          "Failed to initialize cryptographic library (code: \(result))")
      }
      precondition(
        opaqueGetKe1Length() == KE1_LENGTH,
        "KE1 length mismatch: Swift=\(KE1_LENGTH), Rust=\(opaqueGetKe1Length())"
      )
      precondition(
        opaqueGetKe2Length() == KE2_LENGTH,
        "KE2 length mismatch: Swift=\(KE2_LENGTH), Rust=\(opaqueGetKe2Length())"
      )
      precondition(
        opaqueGetKe3Length() == KE3_LENGTH,
        "KE3 length mismatch: Swift=\(KE3_LENGTH), Rust=\(opaqueGetKe3Length())"
      )
      precondition(
        opaqueGetRegistrationRecordLength() == REGISTRATION_RECORD_LENGTH,
        "Registration record length mismatch: Swift=\(REGISTRATION_RECORD_LENGTH), Rust=\(opaqueGetRegistrationRecordLength())"
      )
      initialized = true
    }
  }

  enum ResultCode: Int32 {
    case success = 0
    case invalidInput = -1
    case cryptoError = -2
    case invalidFormat = -3
    case validationError = -4
    case authenticationError = -5
    case invalidPublicKey = -6
    case accountAlreadyRegistered = -7
    case invalidKemInput = -8
    case invalidEnvelopeFormat = -9
    case unsupportedVersion = -10
    case ffiPanic = -99
  }

  static func clientCreate(
    _ serverPublicKey: UnsafePointer<UInt8>,
    _ outHandle: UnsafeMutablePointer<OpaqueClientHandle?>
  ) -> Int32 {
    var err = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&err) }

    return opaqueClientCreate(serverPublicKey, PUBLIC_KEY_LENGTH, outHandle, &err)
  }

  static func clientDestroy(_ handle: OpaqueClientHandle) {
    var h: OpaquePointer? = handle
    opaqueClientDestroy(&h)
  }

  static func registrationRequestCreate(
    _ clientHandle: OpaqueClientHandle,
    _ password: UnsafePointer<UInt8>,
    _ passwordLen: Int,
    _ outStateHandle: UnsafeMutablePointer<RegistrationStateHandle?>,
    _ outRequest: UnsafeMutablePointer<UInt8>
  ) -> Int32 {
    var stateHandle: OpaquePointer?
    var stateErr = OpaqueNativeError(code: 0, message: nil)
    let stateCode = opaqueClientStateCreate(&stateHandle, &stateErr)
    opaqueErrorFree(&stateErr)
    guard stateCode == ResultCode.success.rawValue, let stateHandle else {
      return stateCode
    }

    var reqErr = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&reqErr) }

    let result = opaqueClientCreateRegistrationRequest(
      clientHandle,
      password,
      passwordLen,
      stateHandle,
      outRequest,
      REGISTRATION_REQUEST_LENGTH,
      &reqErr
    )
    if result != ResultCode.success.rawValue {
      var sh: OpaquePointer? = stateHandle
      opaqueClientStateDestroy(&sh)
      return result
    }
    outStateHandle.pointee = stateHandle
    return result
  }

  static func registrationFinalize(
    _ clientHandle: OpaqueClientHandle,
    _ response: UnsafePointer<UInt8>,
    _ stateHandle: RegistrationStateHandle,
    _ outRecord: UnsafeMutablePointer<UInt8>
  ) -> Int32 {
    var err = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&err) }

    return opaqueClientFinalizeRegistration(
      clientHandle,
      response,
      REGISTRATION_RESPONSE_LENGTH,
      stateHandle,
      outRecord,
      REGISTRATION_RECORD_LENGTH,
      &err
    )
  }

  static func registrationStateDestroy(_ handle: RegistrationStateHandle) {
    var h: OpaquePointer? = handle
    opaqueClientStateDestroy(&h)
  }

  static func ke1Generate(
    _ clientHandle: OpaqueClientHandle,
    _ password: UnsafePointer<UInt8>,
    _ passwordLen: Int,
    _ outStateHandle: UnsafeMutablePointer<KeyExchangeStateHandle?>,
    _ outKe1: UnsafeMutablePointer<UInt8>
  ) -> Int32 {
    var stateHandle: OpaquePointer?
    var stateErr = OpaqueNativeError(code: 0, message: nil)
    let stateCode = opaqueClientStateCreate(&stateHandle, &stateErr)
    opaqueErrorFree(&stateErr)
    guard stateCode == ResultCode.success.rawValue, let stateHandle else {
      return stateCode
    }

    var ke1Err = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&ke1Err) }

    let result = opaqueClientGenerateKe1(
      clientHandle,
      password,
      passwordLen,
      stateHandle,
      outKe1,
      KE1_LENGTH,
      &ke1Err
    )
    if result != ResultCode.success.rawValue {
      var sh: OpaquePointer? = stateHandle
      opaqueClientStateDestroy(&sh)
      return result
    }
    outStateHandle.pointee = stateHandle
    return result
  }

  static func ke3Generate(
    _ clientHandle: OpaqueClientHandle,
    _ ke2: UnsafePointer<UInt8>,
    _ stateHandle: KeyExchangeStateHandle,
    _ outKe3: UnsafeMutablePointer<UInt8>
  ) -> Int32 {
    var err = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&err) }

    return opaqueClientGenerateKe3(
      clientHandle,
      ke2,
      KE2_LENGTH,
      stateHandle,
      outKe3,
      KE3_LENGTH,
      &err
    )
  }

  static func deriveMasterKey(
    _ clientHandle: OpaqueClientHandle,
    _ stateHandle: KeyExchangeStateHandle,
    _ outSessionKey: UnsafeMutablePointer<UInt8>,
    _ outMasterKey: UnsafeMutablePointer<UInt8>
  ) -> Int32 {
    var err = OpaqueNativeError(code: 0, message: nil)
    defer { opaqueErrorFree(&err) }

    return opaqueClientFinish(
      clientHandle,
      stateHandle,
      outSessionKey,
      SESSION_KEY_LENGTH,
      outMasterKey,
      MASTER_KEY_LENGTH,
      &err
    )
  }

  static func keStateDestroy(_ handle: KeyExchangeStateHandle) {
    var h: OpaquePointer? = handle
    opaqueClientStateDestroy(&h)
  }

  @inline(never)
  static func secureZero(_ buffer: UnsafeMutablePointer<UInt8>, _ size: Int) {
    guard size > 0 else { return }
    _ = memset_s(buffer, size, 0, size)
  }

  static func secureZeroData(_ data: inout Data) {
    data.withUnsafeMutableBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      secureZero(base.assumingMemoryBound(to: UInt8.self), bytes.count)
    }
  }
}

enum OpaqueError: Error, Sendable {
  case invalidInput(String)
  case cryptoError(String)
  case memoryError(String)
  case validationError(String)
  case authenticationError(String)
  case invalidPublicKey(String)
  case unknownError(Int32)

  static func from(resultCode: Int32, context: String = "") -> OpaqueError {
    guard let code = OpaqueNative.ResultCode(rawValue: resultCode) else {
      return .unknownError(resultCode)
    }

    let message: String = context.isEmpty ? code.description : "\(context): \(code.description)"
    switch code {
    case .success:
      return .unknownError(resultCode)
    case .invalidInput:
      return .invalidInput(message)
    case .cryptoError:
      return .cryptoError(message)
    case .invalidFormat:
      return .cryptoError(message)
    case .validationError:
      return .validationError(message)
    case .authenticationError:
      return .authenticationError(message)
    case .invalidPublicKey:
      return .invalidPublicKey(message)
    case .accountAlreadyRegistered:
      return .validationError(message)
    case .invalidKemInput:
      return .cryptoError(message)
    case .invalidEnvelopeFormat:
      return .cryptoError(message)
    case .unsupportedVersion:
      return .cryptoError(message)
    case .ffiPanic:
      return .cryptoError(message)
    }
  }

  var message: String {
    switch self {
    case .invalidInput(let msg),
      .cryptoError(let msg),
      .memoryError(let msg),
      .validationError(let msg),
      .authenticationError(let msg),
      .invalidPublicKey(let msg):
      return msg
    case .unknownError(let code):
      return "Unknown OPAQUE error: \(code)"
    }
  }
}

extension OpaqueNative.ResultCode: CustomStringConvertible {

  var description: String {
    switch self {
    case .success:
      return "Success"
    case .invalidInput:
      return "Invalid input"
    case .cryptoError:
      return "Cryptographic error"
    case .invalidFormat:
      return "Invalid format"
    case .validationError:
      return "Validation error"
    case .authenticationError:
      return "Authentication error"
    case .invalidPublicKey:
      return "Invalid public key"
    case .accountAlreadyRegistered:
      return "Account already registered"
    case .invalidKemInput:
      return "Invalid KEM input"
    case .invalidEnvelopeFormat:
      return "Invalid envelope format"
    case .unsupportedVersion:
      return "Unsupported protocol version"
    case .ffiPanic:
      return "Internal FFI panic"
    }
  }
}

extension OpaqueError {

  func toAuthenticationFailure() -> AuthenticationFailure {
    switch self {
    case .invalidInput, .validationError:
      return .invalidCredentials(message)
    case .authenticationError:
      return .invalidCredentials("Authentication failed")
    case .cryptoError, .memoryError, .invalidPublicKey, .unknownError:
      return .unexpectedError(message)
    }
  }
}
