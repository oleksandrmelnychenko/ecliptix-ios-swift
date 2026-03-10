// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class ManagedHandle<Tag>: @unchecked Sendable {

  private var handle: EPPNative.EppHandle?
  private let lock = NSLock()
  private var isDestroyed = false
  private let destroyFn: (UnsafeMutablePointer<EPPNative.EppHandle?>) -> Void

  init(
    handle: EPPNative.EppHandle,
    destroy: @escaping (UnsafeMutablePointer<EPPNative.EppHandle?>) -> Void
  ) {
    self.handle = handle
    self.destroyFn = destroy
  }

  deinit {
    destroy()
  }

  func destroy() {
    lock.lock()
    defer { lock.unlock() }

    guard !isDestroyed else { return }
    destroyFn(&handle)
    isDestroyed = true
  }

  func withHandle<T>(_ body: (EPPNative.EppHandle) throws -> T) throws -> T {
    lock.lock()
    defer { lock.unlock() }

    guard !isDestroyed, let h = handle else {
      throw CryptoEngineError.nullHandle(operation: "withHandle")
    }
    return try body(h)
  }

  func consumeHandle() -> EPPNative.EppHandle? {
    lock.lock()
    defer { lock.unlock() }

    guard !isDestroyed, let h = handle else { return nil }
    handle = nil
    isDestroyed = true
    return h
  }
}

enum GroupSessionTag {}
enum IdentityHandleTag {}
enum KeyPackageSecretsTag {}

typealias ManagedGroupSession = ManagedHandle<GroupSessionTag>
typealias ManagedIdentityHandle = ManagedHandle<IdentityHandleTag>
typealias ManagedKeyPackageSecrets = ManagedHandle<KeyPackageSecretsTag>

extension ManagedHandle where Tag == GroupSessionTag {

  convenience init(handle: EPPNative.EppHandle) {
    self.init(handle: handle, destroy: EPPNative.groupDestroy)
  }
}

extension ManagedHandle where Tag == IdentityHandleTag {

  convenience init(handle: EPPNative.EppHandle) {
    self.init(handle: handle, destroy: EPPNative.identityDestroy)
  }
}

extension ManagedHandle where Tag == KeyPackageSecretsTag {

  convenience init(handle: EPPNative.EppHandle) {
    self.init(handle: handle, destroy: EPPNative.groupKeyPackageSecretsDestroy)
  }
}
