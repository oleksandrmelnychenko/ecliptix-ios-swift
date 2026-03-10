// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtocolC
import Foundation

final class EcliptixIdentityKeys: @unchecked Sendable {

  private let handle: EPPNative.EppHandle
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init() throws {
    var handle: OpaquePointer?
    var outError = EcliptixProtocolC.EppError(code: EPP_SUCCESS, message: nil)
    let resultCode = epp_identity_create(&handle, &outError)
    defer { epp_error_free(&outError) }

    guard resultCode == EPP_SUCCESS else {
      let msg = outError.message.map { String(cString: $0) } ?? "unknown"
      throw ProtocolError.keyGenerationFailed(
        "Failed to create identity, code=\(resultCode): \(msg)")
    }
    guard let identityHandle = handle else {
      throw ProtocolError.nullPointer("Identity handle is null")
    }
    self.handle = UnsafeMutableRawPointer(identityHandle)
  }

  init(seed: Data) throws {
    guard seed.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidInput(
        "Seed must be \(EPPConstants.SEED_LENGTH) bytes, got \(seed.count)")
    }

    var handle: OpaquePointer?
    var outError = EcliptixProtocolC.EppError(code: EPP_SUCCESS, message: nil)
    let resultCode = seed.withUnsafeBytes { seedBytes in
      epp_identity_create_from_seed(
        seedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
        seed.count,
        &handle,
        &outError
      )
    }
    defer { epp_error_free(&outError) }

    guard resultCode == EPP_SUCCESS else {
      let msg = outError.message.map { String(cString: $0) } ?? "unknown"
      throw ProtocolError.keyGenerationFailed(
        "Failed to create identity from seed, code=\(resultCode): \(msg)")
    }
    guard let identityHandle = handle else {
      throw ProtocolError.nullPointer("Identity handle is null")
    }
    self.handle = UnsafeMutableRawPointer(identityHandle)
  }

  init(seed: Data, membershipId: String) throws {
    guard seed.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidInput(
        "Seed must be \(EPPConstants.SEED_LENGTH) bytes, got \(seed.count)")
    }
    guard !membershipId.isEmpty else {
      throw ProtocolError.invalidInput("Membership ID cannot be empty")
    }

    var handle: OpaquePointer?
    var outError = EcliptixProtocolC.EppError(code: EPP_SUCCESS, message: nil)
    let resultCode = seed.withUnsafeBytes { seedBytes in
      membershipId.withCString { membershipCString in
        epp_identity_create_with_context(
          seedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          seed.count,
          membershipCString,
          membershipId.utf8.count,
          &handle,
          &outError
        )
      }
    }
    defer { epp_error_free(&outError) }

    guard resultCode == EPP_SUCCESS else {
      let msg = outError.message.map { String(cString: $0) } ?? "unknown"
      throw ProtocolError.keyGenerationFailed(
        "Failed to create identity with context, code=\(resultCode): \(msg)")
    }
    guard let identityHandle = handle else {
      throw ProtocolError.nullPointer("Identity handle is null")
    }
    self.handle = UnsafeMutableRawPointer(identityHandle)
  }

  func getX25519PublicKey() throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Identity already disposed")
    }

    var keyBytes: [UInt8] = [UInt8](repeating: 0, count: EPPConstants.X25519_PUBLIC_KEY_LENGTH)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = keyBytes.withUnsafeMutableBytes {
      (keyBuffer: UnsafeMutableRawBufferPointer) in
      guard let keyPointer = keyBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.identityGetX25519Public(
        handle,
        keyPointer,
        EPPConstants.X25519_PUBLIC_KEY_LENGTH,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to get X25519 public key")
    }
    return Data(keyBytes)
  }

  func getEd25519PublicKey() throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Identity already disposed")
    }

    var keyBytes: [UInt8] = [UInt8](repeating: 0, count: EPPConstants.ED25519_PUBLIC_KEY_LENGTH)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = keyBytes.withUnsafeMutableBytes {
      (keyBuffer: UnsafeMutableRawBufferPointer) in
      guard let keyPointer = keyBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.identityGetEd25519Public(
        handle,
        keyPointer,
        EPPConstants.ED25519_PUBLIC_KEY_LENGTH,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to get Ed25519 public key")
    }
    return Data(keyBytes)
  }

  func getKyberPublicKey() throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Identity already disposed")
    }

    var keyBytes: [UInt8] = [UInt8](repeating: 0, count: EPPConstants.KYBER_PUBLIC_KEY_LENGTH)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = keyBytes.withUnsafeMutableBytes {
      (keyBuffer: UnsafeMutableRawBufferPointer) in
      guard let keyPointer = keyBuffer.bindMemory(to: UInt8.self).baseAddress else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.identityGetKyberPublic(
        handle,
        keyPointer,
        EPPConstants.KYBER_PUBLIC_KEY_LENGTH,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to get Kyber public key")
    }
    return Data(keyBytes)
  }

  func createPrekeyBundle() throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Identity already disposed")
    }

    var buffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = EPPNative.prekeyBundleCreate(
      handle,
      &buffer,
      &errorCode
    )
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to create prekey bundle")
    }
    guard let bufferData: UnsafeMutablePointer<UInt8> = buffer.data, buffer.length > 0 else {
      throw ProtocolError.bufferTooSmall("Prekey bundle buffer is empty")
    }

    let bundleData: Data = Data(bytes: bufferData, count: buffer.length)
    var mutableBuffer: EPPNative.EppBuffer = buffer
    EPPNative.bufferRelease(&mutableBuffer)
    return bundleData
  }

  func withHandle<T>(_ body: (EPPNative.EppHandle) throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Identity accessed after disposal")
    }
    return try body(handle)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    var mutableHandle: EPPNative.EppHandle? = handle
    EPPNative.identityDestroy(&mutableHandle)
  }

  deinit {
    dispose()
  }
}

struct EcliptixIdentityKeysWrapper {

  let publicKey: Data

  static func from(identity: EcliptixIdentityKeys) throws -> EcliptixIdentityKeysWrapper {
    let x25519Public: Data = try identity.getX25519PublicKey()
    return EcliptixIdentityKeysWrapper(publicKey: x25519Public)
  }
}
