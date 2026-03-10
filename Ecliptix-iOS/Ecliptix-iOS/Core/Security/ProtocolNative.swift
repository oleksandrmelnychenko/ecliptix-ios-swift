// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum ProtocolNative {

  static let MASTER_KEY_LENGTH: Int = 64
  static let SESSION_KEY_LENGTH: Int = 64
  static let ACCOUNT_ID_LENGTH: Int = 16
  static let SEALED_OVERHEAD: Int = 48
  static let AES_KEY_LENGTH: Int = 32
  static let AES_NONCE_LENGTH: Int = 12
  static let AES_TAG_LENGTH: Int = 16
  static let X25519_PUBLIC_KEY_LENGTH: Int = 32
  static let ED25519_SIGNATURE_LENGTH: Int = 64
  static let KYBER_PUBLIC_KEY_LENGTH: Int = 1184
  static let KYBER_CIPHERTEXT_LENGTH: Int = 1088
  enum ResultCode: Int32 {
    case success = 0
    case invalidParameters = -1
    case encryptionFailed = -2
    case decryptionFailed = -3
    case invalidState = -4
    case memoryAllocationFailed = -5
    case invalidPublicKey = -6
    case invalidSignature = -7
    case handshakeFailed = -8
  }
  typealias ProtocolStateHandle = UnsafeMutableRawPointer
  @_silgen_name("ecliptix_protocol_create")
  private static func ecliptixProtocolCreate(
    _ masterKey: UnsafePointer<UInt8>,
    _ accountId: UnsafePointer<UInt8>,
    _ stateHandle: UnsafeMutablePointer<ProtocolStateHandle?>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_seal_state")
  private static func ecliptixProtocolSealState(
    _ stateHandle: ProtocolStateHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLen: Int,
    _ sealedOut: UnsafeMutablePointer<UInt8>,
    _ sealedLen: Int
  ) -> Int32
  @_silgen_name("ecliptix_protocol_unseal_state")
  private static func ecliptixProtocolUnsealState(
    _ stateHandle: ProtocolStateHandle,
    _ sealed: UnsafePointer<UInt8>,
    _ sealedLen: Int,
    _ plaintextOut: UnsafeMutablePointer<UInt8>,
    _ plaintextLen: Int
  ) -> Int32
  @_silgen_name("ecliptix_protocol_destroy")
  private static func ecliptixProtocolDestroy(_ stateHandle: ProtocolStateHandle)
  @_silgen_name("ecliptix_protocol_encrypt")
  private static func ecliptixProtocolEncrypt(
    _ stateHandle: ProtocolStateHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLen: Int,
    _ ciphertextOut: UnsafeMutablePointer<UInt8>,
    _ ciphertextLen: Int
  ) -> Int32
  @_silgen_name("ecliptix_protocol_decrypt")
  private static func ecliptixProtocolDecrypt(
    _ stateHandle: ProtocolStateHandle,
    _ ciphertext: UnsafePointer<UInt8>,
    _ ciphertextLen: Int,
    _ plaintextOut: UnsafeMutablePointer<UInt8>,
    _ plaintextLen: Int
  ) -> Int32
  @_silgen_name("ecliptix_protocol_derive_key")
  private static func ecliptixProtocolDeriveKey(
    _ masterKey: UnsafePointer<UInt8>,
    _ accountId: UnsafePointer<UInt8>,
    _ purpose: UnsafePointer<CChar>,
    _ derivedKeyOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_derive_session_key")
  private static func ecliptixProtocolDeriveSessionKey(
    _ masterKey: UnsafePointer<UInt8>,
    _ connectId: UInt32,
    _ sessionKeyOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_ratchet_forward")
  private static func ecliptixProtocolRatchetForward(_ stateHandle: ProtocolStateHandle) -> Int32
  @_silgen_name("ecliptix_protocol_get_epoch")
  private static func ecliptixProtocolGetEpoch(
    _ stateHandle: ProtocolStateHandle,
    _ epochOut: UnsafeMutablePointer<UInt64>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_handshake_init")
  private static func ecliptixProtocolHandshakeInit(
    _ stateHandle: ProtocolStateHandle,
    _ publicKeyOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_handshake_complete")
  private static func ecliptixProtocolHandshakeComplete(
    _ stateHandle: ProtocolStateHandle,
    _ peerPublicKey: UnsafePointer<UInt8>,
    _ sharedSecretOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_aes_encrypt")
  private static func ecliptixProtocolAesEncrypt(
    _ key: UnsafePointer<UInt8>,
    _ nonce: UnsafePointer<UInt8>,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLen: Int,
    _ ciphertextOut: UnsafeMutablePointer<UInt8>,
    _ tagOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_aes_decrypt")
  private static func ecliptixProtocolAesDecrypt(
    _ key: UnsafePointer<UInt8>,
    _ nonce: UnsafePointer<UInt8>,
    _ ciphertext: UnsafePointer<UInt8>,
    _ ciphertextLen: Int,
    _ tag: UnsafePointer<UInt8>,
    _ plaintextOut: UnsafeMutablePointer<UInt8>
  ) -> Int32
  @_silgen_name("ecliptix_protocol_secure_zero")
  private static func ecliptixProtocolSecureZero(_ buffer: UnsafeMutableRawPointer, _ length: Int)
  @_silgen_name("ecliptix_protocol_secure_alloc")
  private static func ecliptixProtocolSecureAlloc(_ size: Int) -> UnsafeMutableRawPointer?
  @_silgen_name("ecliptix_protocol_secure_free")
  private static func ecliptixProtocolSecureFree(_ pointer: UnsafeMutableRawPointer)

  static func createState(
    masterKey: Data,
    accountId: UUID
  ) -> Result<ProtocolStateHandle, ProtocolNativeError> {
    guard masterKey.count == MASTER_KEY_LENGTH else {
      return .failure(.invalidParameters("Master key must be \(MASTER_KEY_LENGTH) bytes"))
    }

    var accountIdBytes = accountId.protobufBytes
    defer { OpaqueNative.secureZeroData(&accountIdBytes) }

    guard accountIdBytes.count == ACCOUNT_ID_LENGTH else {
      return .failure(.invalidParameters("Account ID must be \(ACCOUNT_ID_LENGTH) bytes"))
    }

    var stateHandle: ProtocolStateHandle?
    let resultCode: Int32 = masterKey.withUnsafeBytes { keyBytes in
      accountIdBytes.withUnsafeBytes { idBytes in
        guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let idBase = idBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolCreate(keyBase, idBase, &stateHandle)
      }
    }
    if resultCode == ResultCode.success.rawValue, let handle = stateHandle {
      return .success(handle)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Failed to create protocol state")
      )
    }
  }

  static func sealState(
    stateHandle: ProtocolStateHandle,
    plaintext: Data
  ) -> Result<Data, ProtocolNativeError> {
    let sealedLength: Int = plaintext.count + SEALED_OVERHEAD
    var sealed = Data(count: sealedLength)
    let resultCode: Int32 = plaintext.withUnsafeBytes { plaintextBytes in
      sealed.withUnsafeMutableBytes { sealedBytes in
        guard let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let sealedBase = sealedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolSealState(
          stateHandle, plaintextBase, plaintext.count, sealedBase, sealedLength
        )
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(sealed)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Seal operation failed"))
    }
  }

  static func unsealState(
    stateHandle: ProtocolStateHandle,
    sealed: Data
  ) -> Result<Data, ProtocolNativeError> {
    guard sealed.count >= SEALED_OVERHEAD else {
      return .failure(.invalidParameters("Sealed data too short"))
    }

    let plaintextLength: Int = sealed.count - SEALED_OVERHEAD
    var plaintext = Data(count: plaintextLength)
    let resultCode: Int32 = sealed.withUnsafeBytes { sealedBytes in
      plaintext.withUnsafeMutableBytes { plaintextBytes in
        guard let sealedBase = sealedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolUnsealState(
          stateHandle, sealedBase, sealed.count, plaintextBase, plaintextLength
        )
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(plaintext)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Unseal operation failed"))
    }
  }

  static func destroyState(_ stateHandle: ProtocolStateHandle) {
    ecliptixProtocolDestroy(stateHandle)
  }

  static func encrypt(
    stateHandle: ProtocolStateHandle,
    plaintext: Data
  ) -> Result<Data, ProtocolNativeError> {
    let ciphertextLength: Int = plaintext.count + AES_TAG_LENGTH + AES_NONCE_LENGTH
    var ciphertext = Data(count: ciphertextLength)
    let resultCode: Int32 = plaintext.withUnsafeBytes { plaintextBytes in
      ciphertext.withUnsafeMutableBytes { ciphertextBytes in
        guard let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let ciphertextBase = ciphertextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolEncrypt(
          stateHandle, plaintextBase, plaintext.count, ciphertextBase, ciphertextLength
        )
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(ciphertext)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Encryption failed"))
    }
  }

  static func decrypt(
    stateHandle: ProtocolStateHandle,
    ciphertext: Data
  ) -> Result<Data, ProtocolNativeError> {
    let overhead: Int = AES_TAG_LENGTH + AES_NONCE_LENGTH
    guard ciphertext.count >= overhead else {
      return .failure(.invalidParameters("Ciphertext too short"))
    }

    let plaintextLength: Int = ciphertext.count - overhead
    var plaintext = Data(count: plaintextLength)
    let resultCode: Int32 = ciphertext.withUnsafeBytes { ciphertextBytes in
      plaintext.withUnsafeMutableBytes { plaintextBytes in
        guard let ciphertextBase = ciphertextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolDecrypt(
          stateHandle, ciphertextBase, ciphertext.count, plaintextBase, plaintextLength
        )
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(plaintext)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Decryption failed"))
    }
  }

  static func deriveKey(
    masterKey: Data,
    accountId: UUID,
    purpose: String
  ) -> Result<Data, ProtocolNativeError> {
    guard masterKey.count == MASTER_KEY_LENGTH else {
      return .failure(.invalidParameters("Master key must be \(MASTER_KEY_LENGTH) bytes"))
    }

    var accountIdBytes = accountId.protobufBytes
    defer { OpaqueNative.secureZeroData(&accountIdBytes) }

    var derivedKey = Data(count: MASTER_KEY_LENGTH)
    let resultCode: Int32 = masterKey.withUnsafeBytes { keyBytes in
      accountIdBytes.withUnsafeBytes { idBytes in
        derivedKey.withUnsafeMutableBytes { derivedBytes in
          purpose.withCString { purposeCStr in
            guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
              let idBase = idBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
              let derivedBase = derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            else {
              return ResultCode.invalidParameters.rawValue
            }
            return ecliptixProtocolDeriveKey(keyBase, idBase, purposeCStr, derivedBase)
          }
        }
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(derivedKey)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Key derivation failed"))
    }
  }

  static func deriveSessionKey(
    masterKey: Data,
    connectId: UInt32
  ) -> Result<Data, ProtocolNativeError> {
    guard masterKey.count == MASTER_KEY_LENGTH else {
      return .failure(.invalidParameters("Master key must be \(MASTER_KEY_LENGTH) bytes"))
    }

    var sessionKey = Data(count: SESSION_KEY_LENGTH)
    let resultCode: Int32 = masterKey.withUnsafeBytes { keyBytes in
      sessionKey.withUnsafeMutableBytes { sessionBytes in
        guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let sessionBase = sessionBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolDeriveSessionKey(keyBase, connectId, sessionBase)
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(sessionKey)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Session key derivation failed"))
    }
  }

  static func ratchetForward(stateHandle: ProtocolStateHandle) -> Result<Void, ProtocolNativeError>
  {
    let resultCode: Int32 = ecliptixProtocolRatchetForward(stateHandle)
    if resultCode == ResultCode.success.rawValue {
      return .success(())
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Ratchet forward failed"))
    }
  }

  static func getEpoch(stateHandle: ProtocolStateHandle) -> Result<UInt64, ProtocolNativeError> {
    var epoch: UInt64 = 0
    let resultCode: Int32 = ecliptixProtocolGetEpoch(stateHandle, &epoch)
    if resultCode == ResultCode.success.rawValue {
      return .success(epoch)
    } else {
      return .failure(ProtocolNativeError.from(resultCode: resultCode, context: "Get epoch failed"))
    }
  }

  static func handshakeInit(stateHandle: ProtocolStateHandle) -> Result<Data, ProtocolNativeError> {
    var publicKey = Data(count: X25519_PUBLIC_KEY_LENGTH)
    let resultCode: Int32 = publicKey.withUnsafeMutableBytes { keyBytes in
      guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return ResultCode.invalidParameters.rawValue
      }
      return ecliptixProtocolHandshakeInit(stateHandle, keyBase)
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(publicKey)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Handshake init failed"))
    }
  }

  static func handshakeComplete(
    stateHandle: ProtocolStateHandle,
    peerPublicKey: Data
  ) -> Result<Data, ProtocolNativeError> {
    guard peerPublicKey.count == X25519_PUBLIC_KEY_LENGTH else {
      return .failure(
        .invalidParameters("Peer public key must be \(X25519_PUBLIC_KEY_LENGTH) bytes"))
    }

    var sharedSecret = Data(count: AES_KEY_LENGTH)
    let resultCode: Int32 = peerPublicKey.withUnsafeBytes { peerBytes in
      sharedSecret.withUnsafeMutableBytes { secretBytes in
        guard let peerBase = peerBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          let secretBase = secretBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
        else {
          return ResultCode.invalidParameters.rawValue
        }
        return ecliptixProtocolHandshakeComplete(stateHandle, peerBase, secretBase)
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(sharedSecret)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "Handshake complete failed"))
    }
  }

  static func aesEncrypt(
    key: Data,
    nonce: Data,
    plaintext: Data
  ) -> Result<(ciphertext: Data, tag: Data), ProtocolNativeError> {
    guard key.count == AES_KEY_LENGTH else {
      return .failure(.invalidParameters("Key must be \(AES_KEY_LENGTH) bytes"))
    }
    guard nonce.count == AES_NONCE_LENGTH else {
      return .failure(.invalidParameters("Nonce must be \(AES_NONCE_LENGTH) bytes"))
    }

    var ciphertext = Data(count: plaintext.count)
    var tag = Data(count: AES_TAG_LENGTH)
    let resultCode: Int32 = key.withUnsafeBytes { keyBytes in
      nonce.withUnsafeBytes { nonceBytes in
        plaintext.withUnsafeBytes { plaintextBytes in
          ciphertext.withUnsafeMutableBytes { ciphertextBytes in
            tag.withUnsafeMutableBytes { tagBytes in
              guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let nonceBase = nonceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let ciphertextBase = ciphertextBytes.baseAddress?.assumingMemoryBound(
                  to: UInt8.self),
                let tagBase = tagBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
              else {
                return ResultCode.invalidParameters.rawValue
              }
              return ecliptixProtocolAesEncrypt(
                keyBase, nonceBase, plaintextBase, plaintext.count, ciphertextBase, tagBase
              )
            }
          }
        }
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success((ciphertext, tag))
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "AES encryption failed"))
    }
  }

  static func aesDecrypt(
    key: Data,
    nonce: Data,
    ciphertext: Data,
    tag: Data
  ) -> Result<Data, ProtocolNativeError> {
    guard key.count == AES_KEY_LENGTH else {
      return .failure(.invalidParameters("Key must be \(AES_KEY_LENGTH) bytes"))
    }
    guard nonce.count == AES_NONCE_LENGTH else {
      return .failure(.invalidParameters("Nonce must be \(AES_NONCE_LENGTH) bytes"))
    }
    guard tag.count == AES_TAG_LENGTH else {
      return .failure(.invalidParameters("Tag must be \(AES_TAG_LENGTH) bytes"))
    }

    var plaintext = Data(count: ciphertext.count)
    let resultCode: Int32 = key.withUnsafeBytes { keyBytes in
      nonce.withUnsafeBytes { nonceBytes in
        ciphertext.withUnsafeBytes { ciphertextBytes in
          tag.withUnsafeBytes { tagBytes in
            plaintext.withUnsafeMutableBytes { plaintextBytes in
              guard let keyBase = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let nonceBase = nonceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let ciphertextBase = ciphertextBytes.baseAddress?.assumingMemoryBound(
                  to: UInt8.self),
                let tagBase = tagBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                let plaintextBase = plaintextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
              else {
                return ResultCode.invalidParameters.rawValue
              }
              return ecliptixProtocolAesDecrypt(
                keyBase, nonceBase, ciphertextBase, ciphertext.count, tagBase, plaintextBase
              )
            }
          }
        }
      }
    }
    if resultCode == ResultCode.success.rawValue {
      return .success(plaintext)
    } else {
      return .failure(
        ProtocolNativeError.from(resultCode: resultCode, context: "AES decryption failed"))
    }
  }

  static func secureZero(_ buffer: UnsafeMutablePointer<UInt8>, _ length: Int) {
    guard length > 0 else { return }
    ecliptixProtocolSecureZero(buffer, length)
  }

  static func secureAlloc(size: Int) -> UnsafeMutableRawPointer? {
    ecliptixProtocolSecureAlloc(size)
  }

  static func secureFree(_ pointer: UnsafeMutableRawPointer) {
    ecliptixProtocolSecureFree(pointer)
  }
}

enum ProtocolNativeError: Error {
  case invalidParameters(String)
  case encryptionFailed(String)
  case decryptionFailed(String)
  case invalidState(String)
  case memoryAllocationFailed(String)
  case invalidPublicKey(String)
  case invalidSignature(String)
  case handshakeFailed(String)
  case unknownError(Int32)

  static func from(resultCode: Int32, context: String = "") -> ProtocolNativeError {
    guard let code = ProtocolNative.ResultCode(rawValue: resultCode) else {
      return .unknownError(resultCode)
    }

    let message: String = context.isEmpty ? code.description : "\(context): \(code.description)"
    switch code {
    case .success:
      return .unknownError(resultCode)
    case .invalidParameters:
      return .invalidParameters(message)
    case .encryptionFailed:
      return .encryptionFailed(message)
    case .decryptionFailed:
      return .decryptionFailed(message)
    case .invalidState:
      return .invalidState(message)
    case .memoryAllocationFailed:
      return .memoryAllocationFailed(message)
    case .invalidPublicKey:
      return .invalidPublicKey(message)
    case .invalidSignature:
      return .invalidSignature(message)
    case .handshakeFailed:
      return .handshakeFailed(message)
    }
  }

  var message: String {
    switch self {
    case .invalidParameters(let msg),
      .encryptionFailed(let msg),
      .decryptionFailed(let msg),
      .invalidState(let msg),
      .memoryAllocationFailed(let msg),
      .invalidPublicKey(let msg),
      .invalidSignature(let msg),
      .handshakeFailed(let msg):
      return msg
    case .unknownError(let code):
      return "Unknown protocol error: \(code)"
    }
  }
}

extension ProtocolNative.ResultCode: CustomStringConvertible {

  var description: String {
    switch self {
    case .success:
      return "Success"
    case .invalidParameters:
      return "Invalid parameters"
    case .encryptionFailed:
      return "Encryption failed"
    case .decryptionFailed:
      return "Decryption failed"
    case .invalidState:
      return "Invalid state"
    case .memoryAllocationFailed:
      return "Memory allocation failed"
    case .invalidPublicKey:
      return "Invalid public key"
    case .invalidSignature:
      return "Invalid signature"
    case .handshakeFailed:
      return "Handshake failed"
    }
  }
}

extension ProtocolNativeError {

  func toNetworkFailure() -> NetworkFailure {
    switch self {
    case .encryptionFailed, .decryptionFailed:
      return .encryptionError(message)
    case .invalidState, .invalidParameters:
      return .invalidRequest(message)
    case .handshakeFailed, .invalidPublicKey, .invalidSignature:
      return .sslPinningFailed(message)
    case .memoryAllocationFailed, .unknownError:
      return .unexpectedError(message)
    }
  }
}
