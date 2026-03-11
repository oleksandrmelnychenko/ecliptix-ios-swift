// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os

final class ProtocolStateStorage {
  static let shared: ProtocolStateStorage = ProtocolStateStorage(
    encryptionEntropyStore: KeychainSettingsEncryptionEntropyStore.shared
  )
  private let fileManager: FileManager = FileManager.default
  private let lock: NSLock = NSLock()
  private let encryptionEntropyStore: any SettingsEncryptionEntropyStore
  private static let fileProtection = FileProtectionType.completeUnlessOpen
  private static let magicBytes: Data = Data(
    SecureStorageConstants.Header.magicHeader.utf8)

  init(encryptionEntropyStore: any SettingsEncryptionEntropyStore) {
    self.encryptionEntropyStore = encryptionEntropyStore
  }

  private func applicationSupportDirectory() -> URL {
    if let appSupport = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first {
      return appSupport
    }
    AppLogger.security.error(
      "ProtocolStateStorage: application support directory unavailable, falling back to temporary directory"
    )
    return fileManager.temporaryDirectory
  }

  private lazy var storageDirectory: URL = {
    let appSupport: URL = applicationSupportDirectory()
    let stateDir: URL =
      appSupport
      .appendingPathComponent("Ecliptix", isDirectory: true)
      .appendingPathComponent("ProtocolState", isDirectory: true)
    if !fileManager.fileExists(atPath: stateDir.path) {
      do {
        try fileManager.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try fileManager.setAttributes([.protectionKey: Self.fileProtection], ofItemAtPath: stateDir.path)
      } catch {
        AppLogger.security.error(
          "ProtocolStateStorage: failed to create state directory: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
    return stateDir
  }()

  private func stateFileURL(connectId: String, accountId: Data) -> URL {
    let accountHash: String = SHA256.hash(data: accountId)
      .compactMap { String(format: "%02x", $0) }
      .joined()
      .prefix(SecureStorageConstants.Identity.accountHashPrefixLength)
      .lowercased()
    let fileName: String = "session-\(connectId)-\(accountHash).bin"
    return storageDirectory.appendingPathComponent(fileName)
  }

  private func deriveEncryptionKey() -> Result<SymmetricKey, String> {
    let deviceId: UUID = NetworkConfiguration.default.deviceId
    let keyResult = ProtocolStateEncryptionKeyDeriver.deriveKey(
      deviceId: deviceId,
      entropyStore: encryptionEntropyStore
    )
    guard let keyData = keyResult.ok() else {
      return .err(keyResult.err() ?? "Failed to derive protocol-state encryption key")
    }
    return .ok(SymmetricKey(data: keyData))
  }

  private func buildAAD(
    version: UInt32,
    connectId: String,
    deviceId: UUID,
    accountId: Data
  ) -> Data {
    var aad: Data = Data()
    var versionLE: UInt32 = version.littleEndian
    aad.append(Data(bytes: &versionLE, count: 4))
    aad.append(Data(connectId.utf8))
    aad.append(deviceId.protobufBytes)
    aad.append(accountId)
    return aad
  }

  private func computeHMAC(over data: Data, using key: SymmetricKey) -> Data {
    let hmac = HMAC<SHA512>.authenticationCode(for: data, using: key)
    return Data(hmac)
  }

  private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    lhs.withUnsafeBytes { lhsRaw in
      rhs.withUnsafeBytes { rhsRaw in
        let lhsPtr = lhsRaw.bindMemory(to: UInt8.self)
        let rhsPtr = rhsRaw.bindMemory(to: UInt8.self)
        let length = max(lhsPtr.count, rhsPtr.count)
        var diff: UInt8 = 0
        for i in 0..<length {
          let a: UInt8 = i < lhsPtr.count ? lhsPtr[i] : 0
          let b: UInt8 = i < rhsPtr.count ? rhsPtr[i] : 0
          diff |= a ^ b
        }
        diff |= UInt8(truncatingIfNeeded: lhsPtr.count ^ rhsPtr.count)
        return diff == 0
      }
    }
  }

  func saveState(
    _ sealedState: Data,
    externalCounter: UInt64,
    connectId: String,
    accountId: Data
  ) async -> Result<Unit, String> {
    guard !sealedState.isEmpty else {
      return .err("Sealed state cannot be empty")
    }
    guard !connectId.isEmpty else {
      return .err("Connect ID cannot be empty")
    }
    guard accountId.count == AppConstants.Crypto.guidBytesCount else {
      return .err(
        "Account ID must be \(AppConstants.Crypto.guidBytesCount) bytes, got \(accountId.count)")
    }
    return lock.withLock {
      let fileURL: URL = stateFileURL(connectId: connectId, accountId: accountId)
      let keyResult = deriveEncryptionKey()
      guard let key: SymmetricKey = keyResult.ok() else {
        return .err(keyResult.err() ?? "Failed to derive protocol-state encryption key")
      }
      let deviceId: UUID = NetworkConfiguration.default.deviceId
      let version: UInt32 = SecureStorageConstants.Header.currentVersion
      let aad: Data = buildAAD(
        version: version,
        connectId: connectId,
        deviceId: deviceId,
        accountId: accountId
      )
      do {
        var payload = Data(count: 8)
        payload.withUnsafeMutableBytes { ptr in
          ptr.storeBytes(of: externalCounter.littleEndian, as: UInt64.self)
        }
        payload.append(sealedState)
        let sealedBox = try AES.GCM.seal(payload, using: key, authenticating: aad)
        var container: Data = Data()
        container.append(Self.magicBytes)
        var versionLE: UInt32 = version.littleEndian
        container.append(Data(bytes: &versionLE, count: 4))
        container.append(Data(sealedBox.nonce))
        container.append(sealedBox.tag)
        var aadLenLE: UInt32 = UInt32(aad.count).littleEndian
        container.append(Data(bytes: &aadLenLE, count: 4))
        container.append(aad)
        container.append(sealedBox.ciphertext)
        let hmac: Data = computeHMAC(over: container, using: key)
        container.append(hmac)
        try container.write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
          [.protectionKey: Self.fileProtection],
          ofItemAtPath: fileURL.path
        )
        return .ok(Unit.value)
      } catch {
        return .err("Failed to save state: \(error.localizedDescription)")
      }
    }
  }

  func loadState(
    connectId: String,
    accountId: Data
  ) async -> Result<(sealedState: Data, externalCounter: UInt64), String> {
    guard !connectId.isEmpty else {
      return .err("Connect ID cannot be empty")
    }
    guard accountId.count == AppConstants.Crypto.guidBytesCount else {
      return .err(
        "Account ID must be \(AppConstants.Crypto.guidBytesCount) bytes, got \(accountId.count)")
    }
    return lock.withLock {
      let fileURL: URL = stateFileURL(connectId: connectId, accountId: accountId)
      guard fileManager.fileExists(atPath: fileURL.path) else {
        return .err("State file does not exist")
      }
      do {
        let data: Data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
          return .err("State file is empty")
        }
        if data.count >= Self.magicBytes.count,
          data.prefix(Self.magicBytes.count) == Self.magicBytes
        {
          return decryptContainer(data, connectId: connectId, accountId: accountId)
        }
        AppLogger.security.warning(
          "ProtocolStateStorage: rejected unencrypted state file for connectId=\(connectId, privacy: .public)"
        )
        return .err("Unencrypted state file rejected. Please re-authenticate.")
      } catch {
        return .err("Failed to load state: \(error.localizedDescription)")
      }
    }
  }

  private func decryptContainer(
    _ data: Data,
    connectId: String,
    accountId: Data
  ) -> Result<(sealedState: Data, externalCounter: UInt64), String> {
    let keyResult = deriveEncryptionKey()
    guard let key: SymmetricKey = keyResult.ok() else {
      return .err(keyResult.err() ?? "Failed to derive protocol-state encryption key")
    }
    let magicLen: Int = Self.magicBytes.count
    let hmacSize: Int = SecureStorageConstants.Encryption.hmacSha512Size
    let nonceSize: Int = SecureStorageConstants.Encryption.nonceSize
    let tagSize: Int = SecureStorageConstants.Encryption.tagSize
    let minSize: Int = magicLen + 4 + nonceSize + tagSize + 4 + 1 + hmacSize
    guard data.count >= minSize else {
      return .err("Container too small")
    }

    let payloadData: Data = data.prefix(data.count - hmacSize)
    let storedHMAC: Data = data.suffix(hmacSize)
    let computedHMAC: Data = computeHMAC(over: payloadData, using: key)
    guard constantTimeEqual(storedHMAC, computedHMAC) else {
      return .err("HMAC verification failed — data may be tampered")
    }

    var offset: Int = magicLen
    guard offset + 4 <= payloadData.count else { return .err("Truncated version") }
    let version: UInt32 = payloadData.subdata(in: offset..<(offset + 4))
      .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    offset += 4
    guard version == SecureStorageConstants.Header.currentVersion else {
      return .err("Unsupported container version: \(version)")
    }
    guard offset + nonceSize <= payloadData.count else { return .err("Truncated nonce") }
    let nonceData: Data = payloadData.subdata(in: offset..<(offset + nonceSize))
    offset += nonceSize
    guard offset + tagSize <= payloadData.count else { return .err("Truncated tag") }
    let tagData: Data = payloadData.subdata(in: offset..<(offset + tagSize))
    offset += tagSize
    guard offset + 4 <= payloadData.count else { return .err("Truncated AAD length") }
    let aadLen: UInt32 = payloadData.subdata(in: offset..<(offset + 4))
      .withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    offset += 4
    guard offset + Int(aadLen) <= payloadData.count else { return .err("Truncated AAD") }
    let aad: Data = payloadData.subdata(in: offset..<(offset + Int(aadLen)))
    offset += Int(aadLen)
    let ciphertext: Data = payloadData.subdata(in: offset..<payloadData.count)
    do {
      let nonce = try AES.GCM.Nonce(data: nonceData)
      let sealedBox = try AES.GCM.SealedBox(
        nonce: nonce,
        ciphertext: ciphertext,
        tag: tagData
      )
      let decrypted = try AES.GCM.open(sealedBox, using: key, authenticating: aad)
      guard decrypted.count >= 8 else {
        return .err("Decrypted payload is too small to contain counter prefix")
      }

      let counter = decrypted.prefix(8).withUnsafeBytes {
        $0.loadUnaligned(as: UInt64.self).littleEndian
      }
      return .ok((sealedState: Data(decrypted.dropFirst(8)), externalCounter: counter))
    } catch {
      return .err("Failed to decrypt state: \(error.localizedDescription)")
    }
  }

  func deleteState(connectId: String, accountId: Data) async -> Result<Unit, String> {
    guard !connectId.isEmpty else {
      return .err("Connect ID cannot be empty")
    }
    guard accountId.count == AppConstants.Crypto.guidBytesCount else {
      return await deleteStateAllAccounts(connectId: connectId)
    }
    return lock.withLock {
      let fileURL = stateFileURL(connectId: connectId, accountId: accountId)
      guard fileManager.fileExists(atPath: fileURL.path) else {
        return .ok(Unit.value)
      }
      do {
        try fileManager.removeItem(at: fileURL)
        return .ok(Unit.value)
      } catch {
        return .err("Failed to delete state: \(error.localizedDescription)")
      }
    }
  }

  func deleteState(connectId: String) async -> Result<Unit, String> {
    await deleteStateAllAccounts(connectId: connectId)
  }

  private func deleteStateAllAccounts(connectId: String) -> Result<Unit, String> {
    guard !connectId.isEmpty else {
      return .err("Connect ID cannot be empty")
    }
    return lock.withLock {
      do {
        let contents: [URL] = try fileManager.contentsOfDirectory(
          at: storageDirectory,
          includingPropertiesForKeys: nil
        )
        let matchingFiles: [URL] = contents.filter { url in
          url.lastPathComponent.hasPrefix("session-\(connectId)-")
        }
        for fileURL in matchingFiles {
          try fileManager.removeItem(at: fileURL)
        }
        return .ok(Unit.value)
      } catch {
        return .err("Failed to delete state: \(error.localizedDescription)")
      }
    }
  }

  func hasState(connectId: String, accountId: Data) -> Bool {
    guard !connectId.isEmpty, accountId.count == AppConstants.Crypto.guidBytesCount else {
      return false
    }
    lock.lock()
    defer { lock.unlock() }

    let fileURL: URL = stateFileURL(connectId: connectId, accountId: accountId)
    return fileManager.fileExists(atPath: fileURL.path)
  }

  func deleteAllStates() async -> Result<Unit, String> {
    return lock.withLock {
      do {
        let contents: [URL] = try fileManager.contentsOfDirectory(
          at: storageDirectory,
          includingPropertiesForKeys: nil
        )
        for fileURL in contents where fileURL.lastPathComponent.hasPrefix("session-") {
          try fileManager.removeItem(at: fileURL)
        }
        return .ok(Unit.value)
      } catch {
        return .err("Failed to delete all states: \(error.localizedDescription)")
      }
    }
  }
}
