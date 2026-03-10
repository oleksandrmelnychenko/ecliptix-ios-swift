// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

final class RegistrationResult: @unchecked Sendable {

  private let stateHandle: OpaqueNative.RegistrationStateHandle
  private let requestData: Data
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init(stateHandle: OpaqueNative.RegistrationStateHandle, requestData: Data) {
    self.stateHandle = stateHandle
    self.requestData = requestData
  }

  func getRequestCopy() -> Data? {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else { return nil }
    return requestData
  }

  func withHandle<T>(_ body: (OpaqueNative.RegistrationStateHandle) throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("Registration state accessed after disposal")
    }
    return try body(stateHandle)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    OpaqueNative.registrationStateDestroy(stateHandle)
  }

  deinit {
    dispose()
  }
}

final class KeyExchangeResult: @unchecked Sendable {

  private let stateHandle: OpaqueNative.KeyExchangeStateHandle
  private let ke1Data: Data
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init(stateHandle: OpaqueNative.KeyExchangeStateHandle, ke1Data: Data) {
    self.stateHandle = stateHandle
    self.ke1Data = ke1Data
  }

  func getKeyExchangeDataCopy() -> Data? {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else { return nil }
    return ke1Data
  }

  func withHandle<T>(_ body: (OpaqueNative.KeyExchangeStateHandle) throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("Key exchange state accessed after disposal")
    }
    return try body(stateHandle)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    OpaqueNative.keStateDestroy(stateHandle)
  }

  deinit {
    dispose()
  }
}

final class SecureTextBuffer: @unchecked Sendable {

  private var data: Data
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init(_ data: Data) {
    self.data = data
  }

  init(consuming data: inout Data) {
    let moved = data
    data = Data()
    self.data = moved
  }

  var length: Int {
    lock.lock()
    defer { lock.unlock() }

    return data.count
  }

  func withSecureBytes<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> T? {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else { return nil }
    return try data.withUnsafeBytes { (bufferPointer: UnsafeRawBufferPointer) in
      let typedPointer: UnsafeBufferPointer<UInt8> = bufferPointer.bindMemory(to: UInt8.self)
      return try body(typedPointer)
    }
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    data.withUnsafeMutableBytes { bytes in
      guard let base = bytes.baseAddress else { return }
      let ptr = base.assumingMemoryBound(to: UInt8.self)
      OpaqueNative.secureZero(ptr, bytes.count)
    }
    data = Data()
  }

  deinit {
    dispose()
  }
}

final class CryptoSecureMemoryHandle: @unchecked Sendable {

  private var buffer: UnsafeMutablePointer<UInt8>
  let length: Int
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  private init(buffer: UnsafeMutablePointer<UInt8>, length: Int) {
    self.buffer = buffer
    self.length = length
    let mlockResult = mlock(buffer, length)
    if mlockResult != 0 {
      os_log(.fault, "CryptoSecureMemoryHandle: mlock failed, errno=%d length=%d", errno, length)
    }
  }

  static func allocate(_ size: Int) -> Result<CryptoSecureMemoryHandle, CryptoFailure> {
    guard size > 0 else {
      return .err(.memoryAllocationFailed("Cannot allocate zero-size buffer"))
    }

    let buffer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    buffer.initialize(repeating: 0, count: size)
    let handle: CryptoSecureMemoryHandle = CryptoSecureMemoryHandle(buffer: buffer, length: size)
    return .ok(handle)
  }

  func write(_ data: Data) -> Result<Unit, CryptoFailure> {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return .err(.memoryAccessAfterFree("Secure memory accessed after disposal"))
    }
    guard data.count <= length else {
      return .err(.bufferTooSmall("Data size \(data.count) exceeds buffer size \(length)"))
    }
    data.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) in
      guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return }
      buffer.update(from: source, count: data.count)
    }
    return .ok(.value)
  }

  func readBytes(_ count: Int) -> Result<Data, CryptoFailure> {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return .err(.memoryAccessAfterFree("Secure memory accessed after disposal"))
    }
    guard count <= length else {
      return .err(.bufferTooSmall("Read size \(count) exceeds buffer size \(length)"))
    }

    let data: Data = Data(bytes: buffer, count: count)
    return .ok(data)
  }

  func withReadAccess<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> Result<
    T, CryptoFailure
  > {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return .err(.memoryAccessAfterFree("Secure memory accessed after disposal"))
    }

    let bufferPointer: UnsafeBufferPointer<UInt8> = UnsafeBufferPointer(
      start: buffer, count: length)
    let result: T = try body(bufferPointer)
    return .ok(result)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    OpaqueNative.secureZero(buffer, length)
    munlock(buffer, length)
    buffer.deallocate()
  }

  deinit {
    dispose()
  }
}

final class SensitiveBytes: @unchecked Sendable {

  private var buffer: UnsafeMutablePointer<UInt8>
  let length: Int
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  private init(buffer: UnsafeMutablePointer<UInt8>, length: Int) {
    self.buffer = buffer
    self.length = length
    let mlockResult = mlock(buffer, length)
    if mlockResult != 0 {
      os_log(.fault, "SensitiveBytes: mlock failed, errno=%d length=%d", errno, length)
    }
  }

  static func from(_ data: Data) -> Result<SensitiveBytes, CryptoFailure> {
    let size: Int = data.count
    guard size > 0 else {
      return .err(.invalidInput("Cannot create SensitiveBytes from empty data"))
    }

    let buffer: UnsafeMutablePointer<UInt8> = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
    buffer.initialize(repeating: 0, count: size)
    data.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) in
      guard let source = sourceBytes.bindMemory(to: UInt8.self).baseAddress else { return }
      buffer.update(from: source, count: size)
    }

    let sensitive: SensitiveBytes = SensitiveBytes(buffer: buffer, length: size)
    return .ok(sensitive)
  }

  static func consuming(_ data: inout Data) -> Result<SensitiveBytes, CryptoFailure> {
    defer { OpaqueNative.secureZeroData(&data) }

    return from(data)
  }

  func withReadAccess<T>(_ body: (UnsafeBufferPointer<UInt8>) throws -> T) rethrows -> Result<
    T, CryptoFailure
  > {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return .err(.memoryAccessAfterFree("Sensitive bytes accessed after disposal"))
    }

    let bufferPointer: UnsafeBufferPointer<UInt8> = UnsafeBufferPointer(
      start: buffer, count: length)
    let result: T = try body(bufferPointer)
    return .ok(result)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    OpaqueNative.secureZero(buffer, length)
    munlock(buffer, length)
    buffer.deallocate()
  }

  deinit {
    dispose()
  }
}

enum CryptoFailure: Error, Sendable {
  case memoryAllocationFailed(String)
  case memoryAccessAfterFree(String)
  case bufferTooSmall(String)
  case invalidInput(String)
  case cryptographicOperationFailed(String)

  var message: String {
    switch self {
    case .memoryAllocationFailed(let msg),
      .memoryAccessAfterFree(let msg),
      .bufferTooSmall(let msg),
      .invalidInput(let msg),
      .cryptographicOperationFailed(let msg):
      return msg
    }
  }

  func toAuthenticationFailure() -> AuthenticationFailure {
    switch self {
    case .invalidInput:
      return .unexpectedError(message)
    case .memoryAllocationFailed, .memoryAccessAfterFree:
      return .secureMemoryAllocationFailed(message)
    case .bufferTooSmall:
      return .unexpectedError(message)
    case .cryptographicOperationFailed:
      return .unexpectedError(message)
    }
  }
}
