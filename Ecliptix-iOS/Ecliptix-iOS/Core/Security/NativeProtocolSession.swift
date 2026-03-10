// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct ProtocolDecryptResult {
  let plaintext: Data
  let metadata: Data
}

final class NativeProtocolSession: @unchecked Sendable {

  private let handle: EPPNative.EppHandle
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init(handle: EPPNative.EppHandle) {
    self.handle = handle
  }

  static func restore(
    sealedState: Data,
    key: Data,
    minExternalCounter: UInt64
  ) throws -> (session: NativeProtocolSession, externalCounter: UInt64) {
    guard !sealedState.isEmpty else {
      throw ProtocolError.invalidInput("Sealed state cannot be empty")
    }
    guard key.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidInput("Seal key must be \(EPPConstants.SEED_LENGTH) bytes")
    }

    var sessionHandle: EPPNative.EppHandle?
    var outExternalCounter: UInt64 = 0
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = sealedState.withUnsafeBytes { (stateBytes: UnsafeRawBufferPointer) in
      key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) in
        guard let statePointer = stateBytes.bindMemory(to: UInt8.self).baseAddress,
          let keyPointer = keyBytes.bindMemory(to: UInt8.self).baseAddress
        else {
          errorCode = .errorInvalidInput
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.sessionDeserializeSealed(
          statePointer,
          sealedState.count,
          keyPointer,
          key.count,
          minExternalCounter,
          &outExternalCounter,
          &sessionHandle,
          &errorCode
        )
      }
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(
        errorCode: errorCode, message: "Failed to restore session from sealed state")
    }
    guard let handle: EPPNative.EppHandle = sessionHandle else {
      throw ProtocolError.nullPointer("Session handle is null")
    }
    return (NativeProtocolSession(handle: handle), outExternalCounter)
  }

  func encrypt(
    plaintext: Data,
    envelopeType: EPPNative.EppEnvelopeType,
    envelopeId: UInt32,
    correlationId: String? = nil
  ) throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Session already disposed")
    }
    guard !plaintext.isEmpty else {
      throw ProtocolError.invalidInput("Plaintext cannot be empty")
    }

    var encryptedEnvelope: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = plaintext.withUnsafeBytes { (plaintextBytes: UnsafeRawBufferPointer) in
      guard let plaintextPointer = plaintextBytes.bindMemory(to: UInt8.self).baseAddress else {
        errorCode = .errorInvalidInput
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      if let correlationId = correlationId {
        return correlationId.withCString { (correlationCString: UnsafePointer<CChar>) in
          let correlationPointer: UnsafePointer<UInt8> = UnsafeRawPointer(correlationCString)
            .assumingMemoryBound(to: UInt8.self)
          return EPPNative.sessionEncrypt(
            handle,
            plaintextPointer,
            plaintext.count,
            envelopeType.rawValue,
            envelopeId,
            correlationPointer,
            correlationId.utf8.count,
            &encryptedEnvelope,
            &errorCode
          )
        }
      } else {
        return EPPNative.sessionEncrypt(
          handle,
          plaintextPointer,
          plaintext.count,
          envelopeType.rawValue,
          envelopeId,
          nil,
          0,
          &encryptedEnvelope,
          &errorCode
        )
      }
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to encrypt plaintext")
    }
    guard let bufferData: UnsafeMutablePointer<UInt8> = encryptedEnvelope.data,
      encryptedEnvelope.length > 0
    else {
      throw ProtocolError.bufferTooSmall("Encrypted envelope buffer is empty")
    }

    let envelopeData: Data = Data(bytes: bufferData, count: encryptedEnvelope.length)
    var mutableBuffer: EPPNative.EppBuffer = encryptedEnvelope
    EPPNative.bufferRelease(&mutableBuffer)
    return envelopeData
  }

  func decrypt(_ encryptedEnvelope: Data) throws -> ProtocolDecryptResult {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Session already disposed")
    }
    guard !encryptedEnvelope.isEmpty else {
      throw ProtocolError.invalidInput("Encrypted envelope cannot be empty")
    }

    var plaintextBuffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var metadataBuffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = encryptedEnvelope.withUnsafeBytes {
      (envelopeBytes: UnsafeRawBufferPointer) in
      guard let envelopePointer = envelopeBytes.bindMemory(to: UInt8.self).baseAddress else {
        errorCode = .errorInvalidInput
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.sessionDecrypt(
        handle,
        envelopePointer,
        encryptedEnvelope.count,
        &plaintextBuffer,
        &metadataBuffer,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to decrypt envelope")
    }
    guard let plaintextData: UnsafeMutablePointer<UInt8> = plaintextBuffer.data,
      plaintextBuffer.length > 0
    else {
      throw ProtocolError.bufferTooSmall("Plaintext buffer is empty")
    }

    let plaintext: Data = Data(bytes: plaintextData, count: plaintextBuffer.length)
    var mutablePlaintextBuffer: EPPNative.EppBuffer = plaintextBuffer
    EPPNative.bufferRelease(&mutablePlaintextBuffer)
    let metadata: Data
    if let metadataData: UnsafeMutablePointer<UInt8> = metadataBuffer.data,
      metadataBuffer.length > 0
    {
      metadata = Data(bytes: metadataData, count: metadataBuffer.length)
      var mutableMetadataBuffer: EPPNative.EppBuffer = metadataBuffer
      EPPNative.bufferRelease(&mutableMetadataBuffer)
    } else {
      metadata = Data()
    }
    return ProtocolDecryptResult(plaintext: plaintext, metadata: metadata)
  }

  func exportSealedState(key: Data, externalCounter: UInt64) throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Session already disposed")
    }
    guard key.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidInput("Seal key must be \(EPPConstants.SEED_LENGTH) bytes")
    }

    var sealedStateBuffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = key.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) in
      guard let keyPointer = keyBytes.bindMemory(to: UInt8.self).baseAddress else {
        errorCode = .errorInvalidInput
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.sessionSerializeSealed(
        handle,
        keyPointer,
        key.count,
        externalCounter,
        &sealedStateBuffer,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(
        errorCode: errorCode, message: "Failed to serialize session to sealed state")
    }
    guard let bufferData: UnsafeMutablePointer<UInt8> = sealedStateBuffer.data,
      sealedStateBuffer.length > 0
    else {
      throw ProtocolError.bufferTooSmall("Sealed state buffer is empty")
    }

    let sealedState: Data = Data(bytes: bufferData, count: sealedStateBuffer.length)
    var mutableBuffer: EPPNative.EppBuffer = sealedStateBuffer
    EPPNative.bufferRelease(&mutableBuffer)
    return sealedState
  }

  static func validateEnvelope(_ encryptedEnvelope: Data) throws {
    guard !encryptedEnvelope.isEmpty else {
      throw ProtocolError.invalidInput("Encrypted envelope cannot be empty")
    }

    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = encryptedEnvelope.withUnsafeBytes {
      (envelopeBytes: UnsafeRawBufferPointer) in
      guard let envelopePointer = envelopeBytes.bindMemory(to: UInt8.self).baseAddress else {
        errorCode = .errorInvalidInput
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.envelopeValidate(
        envelopePointer,
        encryptedEnvelope.count,
        &errorCode
      )
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Envelope validation failed")
    }
  }

  func withHandle<T>(_ body: (EPPNative.EppHandle) throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Session accessed after disposal")
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
    EPPNative.sessionDestroy(&mutableHandle)
  }

  deinit {
    dispose()
  }
}
