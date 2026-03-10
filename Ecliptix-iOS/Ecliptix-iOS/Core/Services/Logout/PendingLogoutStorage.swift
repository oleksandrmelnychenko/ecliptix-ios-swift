// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import os.log

struct PendingLogoutRecord: Codable {

  let requestData: Data
  let networkConfiguration: NetworkConfiguration?
}

final class PendingLogoutStorage {

  static let shared = PendingLogoutStorage()
  private let defaultsKey = "ecliptix.pending.logout.v2"
  private let keychainAccount = "ecliptix.pending.logout.key"
  private let keychainService = AppConstants.Keychain.serviceName
  private let lock = NSLock()

  private init() {}

  func storePendingLogout(_ requestData: Data, networkConfiguration: NetworkConfiguration?) {
    lock.withLock {
      guard let key = getOrCreateEncryptionKeyForStore() else { return }
      do {
        let record = PendingLogoutRecord(
          requestData: requestData,
          networkConfiguration: networkConfiguration
        )
        let encoded = try JSONEncoder().encode(record)
        let sealed = try ChaChaPoly.seal(encoded, using: key)
        UserDefaults.standard.set(sealed.combined.base64EncodedString(), forKey: defaultsKey)
      } catch {
        AppLogger.auth.error(
          "PendingLogoutStorage: encryption failed, pending logout not stored: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
  }

  func getPendingLogoutRecord() -> PendingLogoutRecord? {
    lock.withLock {
      guard let encoded = UserDefaults.standard.string(forKey: defaultsKey),
        let combined = Data(base64Encoded: encoded),
        let key = loadEncryptionKey()
      else { return nil }
      do {
        let sealedBox = try ChaChaPoly.SealedBox(combined: combined)
        let decrypted = try ChaChaPoly.open(sealedBox, using: key)
        return try JSONDecoder().decode(PendingLogoutRecord.self, from: decrypted)
      } catch {
        AppLogger.auth.error(
          "PendingLogoutStorage: decryption failed, returning nil: \(error.localizedDescription, privacy: .public)"
        )
        return nil
      }
    }
  }

  func getPendingLogout() -> Data? {
    getPendingLogoutRecord()?.requestData
  }

  func clearPendingLogout() {
    lock.withLock {
      UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
  }

  var hasPendingLogout: Bool {
    lock.withLock {
      UserDefaults.standard.string(forKey: defaultsKey) != nil
    }
  }

  private func getOrCreateEncryptionKeyForStore() -> SymmetricKey? {
    if let data = loadEncryptionKeyData() {
      return SymmetricKey(data: data)
    }

    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    guard persistEncryptionKey(keyData) else {
      AppLogger.auth.error("PendingLogoutStorage: failed to persist encryption key")
      return nil
    }
    return key
  }

  private func loadEncryptionKey() -> SymmetricKey? {
    guard let data = loadEncryptionKeyData() else {
      AppLogger.auth.warning(
        "PendingLogoutStorage: encryption key unavailable while loading pending logout"
      )
      return nil
    }
    return SymmetricKey(data: data)
  }

  private func loadEncryptionKeyData() -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return data
  }

  private func persistEncryptionKey(_ data: Data) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: keychainService,
      kSecAttrAccount as String: keychainAccount,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
    SecItemDelete(query as CFDictionary)
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      AppLogger.auth.error(
        "PendingLogoutStorage: failed to persist key, status=\(status, privacy: .public)")
      return false
    }
    return loadEncryptionKeyData() == data
  }
}
