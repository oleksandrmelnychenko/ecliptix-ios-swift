// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Security

final class KeychainStorage: SecureStorageProvider {

  private let service: String
  private let accessGroup: String?

  init(
    service: String = Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    accessGroup: String? = nil
  ) {
    self.service = service
    self.accessGroup = accessGroup
  }

  func store(key: String, data: Data) async throws {
    let query = buildQuery(for: key)
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
      let attributesToUpdate: [String: Any] = [
        kSecValueData as String: data
      ]
      let updateStatus = SecItemUpdate(
        query as CFDictionary,
        attributesToUpdate as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw KeychainError.updateFailed(status: updateStatus)
      }
    } else {
      var addQuery = query
      addQuery[kSecValueData as String] = data
      let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
      guard addStatus == errSecSuccess else {
        throw KeychainError.addFailed(status: addStatus)
      }
    }
  }

  func retrieve(key: String) async throws -> Data? {
    var query = buildQuery(for: key)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw KeychainError.retrieveFailed(status: status)
    }
    guard let data = result as? Data else {
      throw KeychainError.invalidData
    }
    return data
  }

  func delete(key: String) async throws {
    let query = buildQuery(for: key)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.deleteFailed(status: status)
    }
  }

  func exists(key: String) async -> Bool {
    let query = buildQuery(for: key)
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  private func buildQuery(for key: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    if let accessGroup = accessGroup {
      query[kSecAttrAccessGroup as String] = accessGroup
    }
    return query
  }
}

enum KeychainError: Error, LocalizedError {
  case addFailed(status: OSStatus)
  case updateFailed(status: OSStatus)
  case retrieveFailed(status: OSStatus)
  case deleteFailed(status: OSStatus)
  case invalidData
  var errorDescription: String? {
    switch self {
    case .addFailed(let status):
      return "Failed to add item to keychain: \(status)"
    case .updateFailed(let status):
      return "Failed to update keychain item: \(status)"
    case .retrieveFailed(let status):
      return "Failed to retrieve keychain item: \(status)"
    case .deleteFailed(let status):
      return "Failed to delete keychain item: \(status)"
    case .invalidData:
      return "Invalid data retrieved from keychain"
    }
  }
}
