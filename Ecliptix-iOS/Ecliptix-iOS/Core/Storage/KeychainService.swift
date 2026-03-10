// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Security

final class KeychainService {

  static let shared: KeychainService = KeychainService()
  private let serviceName: String = AppConstants.Keychain.serviceName
  private let masterKeySharePrefix: String = AppConstants.Keychain.masterKeySharePrefix
  private let masterKeyShareCount: Int = AppConstants.Keychain.masterKeyShareCount

  private init() {}

  func save(_ data: Data, forKey key: String) -> Result<Unit, String> {
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let status: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      return .err("Failed to save to keychain: \(status)")
    }
    return .ok(Unit.value)
  }

  func load(forKey key: String) -> Result<Data, String> {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var dataTypeRef: AnyObject?
    let status: OSStatus = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
    guard status == errSecSuccess else {
      if status == errSecItemNotFound {
        return .err("Item not found in keychain")
      }
      return .err("Failed to load from keychain: \(status)")
    }
    guard let data = dataTypeRef as? Data else {
      return .err("Invalid data type in keychain")
    }
    return .ok(data)
  }

  func delete(forKey key: String) -> Result<Unit, String> {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    let status: OSStatus = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      return .err("Failed to delete from keychain: \(status)")
    }
    return .ok(Unit.value)
  }

  func exists(forKey key: String) -> Bool {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecReturnData as String: false,
    ]
    let status: OSStatus = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  func saveMasterKey(_ masterKey: Data, forAccountId accountId: UUID) -> Result<Unit, String> {
    save(masterKey, forKey: "\(AppConstants.Keychain.masterKeyPrefix)-\(accountId.uuidString)")
  }

  func loadMasterKey(forAccountId accountId: UUID) -> Result<Data, String> {
    load(forKey: "\(AppConstants.Keychain.masterKeyPrefix)-\(accountId.uuidString)")
  }

  func deleteMasterKey(forAccountId accountId: UUID) -> Result<Unit, String> {
    delete(forKey: "\(AppConstants.Keychain.masterKeyPrefix)-\(accountId.uuidString)")
  }

  func hasMasterKey(forAccountId accountId: UUID) -> Bool {
    exists(forKey: "\(AppConstants.Keychain.masterKeyPrefix)-\(accountId.uuidString)")
  }

  func saveMasterKeyShares(_ shares: [Data], forAccountId accountId: UUID) -> Result<Unit, String> {
    guard shares.count == masterKeyShareCount else {
      return .err("Expected \(masterKeyShareCount) key shares, got \(shares.count)")
    }
    for (index, share) in shares.enumerated() {
      let saveResult = saveSensitive(
        share, forKey: masterKeyShareStorageKey(index: index + 1, accountId: accountId))
      guard saveResult.isOk else {
        _ = deleteMasterKeyShares(forAccountId: accountId)
        return .err("Failed to save key share \(index + 1): \(saveResult.err() ?? "")")
      }
    }
    return .ok(Unit.value)
  }

  func loadMasterKeyShares(forAccountId accountId: UUID) -> [Data] {
    var shares: [Data] = []
    shares.reserveCapacity(masterKeyShareCount)
    for index in 1...masterKeyShareCount {
      let result = load(forKey: masterKeyShareStorageKey(index: index, accountId: accountId))
      if case .ok(let share) = result {
        shares.append(share)
      }
    }
    return shares
  }

  func deleteMasterKeyShares(forAccountId accountId: UUID) -> Result<Unit, String> {
    for index in 1...masterKeyShareCount {
      let deleteResult = delete(
        forKey: masterKeyShareStorageKey(index: index, accountId: accountId))
      guard deleteResult.isOk else {
        return .err("Failed to delete key share \(index): \(deleteResult.err() ?? "")")
      }
    }
    return .ok(Unit.value)
  }

  func hasAnyMasterKeyShare(forAccountId accountId: UUID) -> Bool {
    for index in 1...masterKeyShareCount {
      if exists(forKey: masterKeyShareStorageKey(index: index, accountId: accountId)) {
        return true
      }
    }
    return false
  }

  private func masterKeyShareStorageKey(index: Int, accountId: UUID) -> String {
    "\(masterKeySharePrefix)-\(index)-\(accountId.uuidString)"
  }

  private func saveSensitive(_ data: Data, forKey key: String) -> Result<Unit, String> {
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
    let status: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard status == errSecSuccess else {
      return .err("Failed to save sensitive keychain item: \(status)")
    }
    return .ok(Unit.value)
  }

  func saveSensitiveWithBiometric(_ data: Data, forKey key: String) -> Result<Unit, String> {
    var error: Unmanaged<CFError>?
    guard
      let accessControl = SecAccessControlCreateWithFlags(
        kCFAllocatorDefault,
        kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        [.biometryCurrentSet, .or, .devicePasscode],
        &error
      )
    else {
      let cfError = error?.takeRetainedValue()
      return .err("Failed to create access control: \(cfError?.localizedDescription ?? "unknown")")
    }

    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessControl as String: accessControl,
      kSecAttrSynchronizable as String: false,
    ]
    let status: OSStatus = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      return .err("Failed to save biometric-protected keychain item: \(status)")
    }
    return .ok(Unit.value)
  }
}
