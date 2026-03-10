// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import os

protocol IdentityMasterKeyStore: AnyObject {

  func hasAnyMasterKeyShare(forAccountId accountId: UUID) -> Bool

  func saveMasterKeyShares(_ shares: [Data], forAccountId accountId: UUID) -> Result<Unit, String>

  func loadMasterKeyShares(forAccountId accountId: UUID) -> [Data]

  func deleteMasterKeyShares(forAccountId accountId: UUID) -> Result<Unit, String>

  func saveShamirAuthKey(_ authKey: Data, forAccountId accountId: UUID) -> Result<Unit, String>

  func loadShamirAuthKey(forAccountId accountId: UUID) -> Result<Data, String>

  func deleteShamirAuthKey(forAccountId accountId: UUID) -> Result<Unit, String>
}

protocol SettingsEncryptionEntropyStore: AnyObject {

  func loadEntropy() -> Result<Data, String>

  func saveEntropy(_ entropy: Data) -> Result<Unit, String>
}

final class KeychainIdentityMasterKeyStore: IdentityMasterKeyStore {

  static let shared = KeychainIdentityMasterKeyStore(keychainService: .shared)

  private let keychainService: KeychainService

  init(keychainService: KeychainService) {
    self.keychainService = keychainService
  }

  func hasAnyMasterKeyShare(forAccountId accountId: UUID) -> Bool {
    keychainService.hasAnyMasterKeyShare(forAccountId: accountId)
  }

  func saveMasterKeyShares(_ shares: [Data], forAccountId accountId: UUID) -> Result<Unit, String> {
    keychainService.saveMasterKeyShares(shares, forAccountId: accountId)
  }

  func loadMasterKeyShares(forAccountId accountId: UUID) -> [Data] {
    keychainService.loadMasterKeyShares(forAccountId: accountId)
  }

  func deleteMasterKeyShares(forAccountId accountId: UUID) -> Result<Unit, String> {
    keychainService.deleteMasterKeyShares(forAccountId: accountId)
  }

  private func shamirAuthKeyName(forAccountId accountId: UUID) -> String {
    "shamir_auth_key_\(accountId.uuidString)"
  }

  func saveShamirAuthKey(_ authKey: Data, forAccountId accountId: UUID) -> Result<Unit, String> {
    keychainService.save(authKey, forKey: shamirAuthKeyName(forAccountId: accountId))
  }

  func loadShamirAuthKey(forAccountId accountId: UUID) -> Result<Data, String> {
    keychainService.load(forKey: shamirAuthKeyName(forAccountId: accountId))
  }

  func deleteShamirAuthKey(forAccountId accountId: UUID) -> Result<Unit, String> {
    keychainService.delete(forKey: shamirAuthKeyName(forAccountId: accountId))
  }
}

final class KeychainSettingsEncryptionEntropyStore: SettingsEncryptionEntropyStore {

  static let shared = KeychainSettingsEncryptionEntropyStore(keychainService: .shared)

  private let keychainService: KeychainService

  init(keychainService: KeychainService) {
    self.keychainService = keychainService
  }

  func loadEntropy() -> Result<Data, String> {
    keychainService.load(forKey: AppConstants.Keychain.settingsEncryptionKeyName)
  }

  func saveEntropy(_ entropy: Data) -> Result<Unit, String> {
    keychainService.save(entropy, forKey: AppConstants.Keychain.settingsEncryptionKeyName)
  }
}

enum ProtocolStateEncryptionKeyDeriver {

  static func deriveKey(
    deviceId: UUID,
    entropyStore: any SettingsEncryptionEntropyStore
  ) -> Result<Data, String> {
    let salt = Data("ecliptix-sealed-state-encryption".utf8)
    let deviceData = deviceId.protobufBytes
    guard let entropy = loadOrCreateEntropy(using: entropyStore).ok() else {
      return .err("Failed to load protocol-state encryption entropy")
    }
    var ikm = Data(capacity: deviceData.count + entropy.count)
    ikm.append(deviceData)
    ikm.append(entropy)
    let derivedKey = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: ikm),
      salt: salt,
      info: Data(),
      outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
    return .ok(derivedKey)
  }

  private static func loadOrCreateEntropy(
    using store: any SettingsEncryptionEntropyStore
  ) -> Result<Data, String> {
    let loadResult = store.loadEntropy()
    if let existing = loadResult.ok() {
      return .ok(existing)
    }
    if let error = loadResult.err(), error != "Item not found in keychain" {
      AppLogger.security.error(
        "Identity infrastructure: failed to load encryption entropy: \(error, privacy: .public)"
      )
      return .err(error)
    }
    AppLogger.security.warning(
      "Identity infrastructure: encryption entropy not found, generating new. Existing encrypted state will be lost."
    )
    var entropy = Data(count: 32)
    let status = entropy.withUnsafeMutableBytes { ptr -> OSStatus in
      guard let base = ptr.baseAddress else { return errSecAllocate }
      return SecRandomCopyBytes(kSecRandomDefault, 32, base)
    }
    guard status == errSecSuccess else {
      AppLogger.security.fault(
        "Identity infrastructure: SecRandomCopyBytes failed status=\(status, privacy: .public)")
      return .err("Failed to generate protocol-state encryption entropy: \(status)")
    }
    let saveResult = store.saveEntropy(entropy)
    guard saveResult.isOk else {
      let error = saveResult.err() ?? "unknown"
      AppLogger.security.error(
        "Identity infrastructure: failed to persist encryption entropy: \(error, privacy: .public)"
      )
      return .err(error)
    }
    return .ok(entropy)
  }
}

enum SealedStateKeyDeriver {

  static func deriveKey(masterKey: Data, membershipId: UUID) throws -> Data {
    try OpaqueRootKeyDerivation.deriveRootKey(
      opaqueSessionKey: masterKey,
      userContext: membershipId.protobufBytes
    )
  }
}
