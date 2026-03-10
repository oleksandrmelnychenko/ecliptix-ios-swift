// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CommonCrypto
import Foundation
import Security

struct NetworkProviderSecurity {

  let retryPolicyProvider: RetryPolicyProvider
  let platformSecurityProvider: PlatformSecurityProvider

  init(
    retryPolicyProvider: RetryPolicyProvider,
    platformSecurityProvider: PlatformSecurityProvider
  ) {
    self.retryPolicyProvider = retryPolicyProvider
    self.platformSecurityProvider = platformSecurityProvider
  }
}

protocol RetryPolicyProvider {

  func getPolicyForOperation(_ operationType: RpcServiceType) -> RetryPolicy
}

struct RetryPolicy {

  let maxRetries: Int
  let initialDelay: TimeInterval
  let maxDelay: TimeInterval
  let backoffMultiplier: Double
  let jitterFactor: Double
  static let `default` = RetryPolicy(
    maxRetries: 3,
    initialDelay: 1.0,
    maxDelay: 30.0,
    backoffMultiplier: 2.0,
    jitterFactor: 0.2
  )
  static let aggressive = RetryPolicy(
    maxRetries: 5,
    initialDelay: 0.5,
    maxDelay: 60.0,
    backoffMultiplier: 2.0,
    jitterFactor: 0.1
  )

  func calculateDelay(attempt: Int) -> TimeInterval {
    let exponentialDelay = initialDelay * pow(backoffMultiplier, Double(attempt))
    let cappedDelay = min(exponentialDelay, maxDelay)
    let jitter = cappedDelay * jitterFactor * (Double.random(in: -1...1))
    return max(0, cappedDelay + jitter)
  }
}

protocol PlatformSecurityProvider {

  func getOrCreateSessionStateKey() async throws -> Data

  func generateSecureRandom(byteCount: Int) async -> Result<Data, CryptographyFailure>

  func deriveKey(from password: Data, salt: Data, iterations: Int, keyLength: Int) async
    -> Result<Data, CryptographyFailure>

  func secureWipe(_ data: inout Data)
}

final class DefaultPlatformSecurityProvider: PlatformSecurityProvider {

  private let sessionStateKeyName = "session_state_encryption_key"
  private let secureStorage: SecureStorageProvider

  init(secureStorage: SecureStorageProvider) {
    self.secureStorage = secureStorage
  }

  func getOrCreateSessionStateKey() async throws -> Data {
    if let existingKey = try await secureStorage.retrieve(key: sessionStateKeyName) {
      return existingKey
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    defer { OpaqueNative.secureZero(&bytes, bytes.count) }

    let status = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
    guard status == errSecSuccess else {
      throw CryptographyFailure.initializationFailed(
        "SecRandomCopyBytes failed with status \(status)")
    }

    let newKey = Data(bytes)
    try await secureStorage.store(key: sessionStateKeyName, data: newKey)
    return newKey
  }

  func getOrCreateSessionStateKeySync() throws -> Data {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ecliptix.app",
      kSecAttrAccount as String: sessionStateKeyName,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data {
      return data
    }
    guard status == errSecItemNotFound else {
      throw CryptographyFailure.initializationFailed(
        "SecItemCopyMatching failed with status \(status)")
    }

    var bytes = [UInt8](repeating: 0, count: 32)
    let genStatus = SecRandomCopyBytes(kSecRandomDefault, 32, &bytes)
    guard genStatus == errSecSuccess else {
      throw CryptographyFailure.initializationFailed("SecRandomCopyBytes failed")
    }

    let newKey = Data(bytes)
    OpaqueNative.secureZero(&bytes, bytes.count)
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ecliptix.app",
      kSecAttrAccount as String: sessionStateKeyName,
      kSecValueData as String: newKey,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
    if addStatus == errSecDuplicateItem {
      var existing: AnyObject?
      let readStatus = SecItemCopyMatching(query as CFDictionary, &existing)
      if readStatus == errSecSuccess, let existingKey = existing as? Data {
        return existingKey
      }
      throw CryptographyFailure.initializationFailed(
        "SecItemCopyMatching after duplicate failed with status \(readStatus)")
    }
    guard addStatus == errSecSuccess else {
      throw CryptographyFailure.initializationFailed("SecItemAdd failed with status \(addStatus)")
    }
    return newKey
  }

  func generateSecureRandom(byteCount: Int) async -> Result<Data, CryptographyFailure> {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    defer { OpaqueNative.secureZero(&bytes, bytes.count) }

    let result = SecRandomCopyBytes(kSecRandomDefault, byteCount, &bytes)
    if result == errSecSuccess {
      return .ok(Data(bytes))
    } else {
      return .err(.initializationFailed("Failed to generate secure random bytes"))
    }
  }

  func deriveKey(
    from password: Data,
    salt: Data,
    iterations: Int,
    keyLength: Int
  ) async -> Result<Data, CryptographyFailure> {
    guard iterations >= 600_000 else {
      return .err(.invalidOperation("PBKDF2 iterations must be >= 600,000, got \(iterations)"))
    }

    var derivedKey = Data(count: keyLength)
    let result = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
      password.withUnsafeBytes { passwordBytes in
        salt.withUnsafeBytes { saltBytes in
          CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
            password.count,
            saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            UInt32(iterations),
            derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            keyLength
          )
        }
      }
    }
    if result == kCCSuccess {
      return .ok(derivedKey)
    } else {
      return .err(.invalidOperation("PBKDF2 derivation failed"))
    }
  }

  func secureWipe(_ data: inout Data) {
    OpaqueNative.secureZeroData(&data)
    data.removeAll()
  }
}
