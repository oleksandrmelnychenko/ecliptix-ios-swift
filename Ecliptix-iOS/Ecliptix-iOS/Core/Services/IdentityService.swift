// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import os

final class IdentityService {

  static let shared = IdentityService(
    masterKeyStore: KeychainIdentityMasterKeyStore.shared,
    secureStorageService: .shared,
    protocolStateStorage: .shared
  )

  private static let masterKeyShareThreshold: UInt8 = 2
  private static let masterKeyShareCount: UInt8 = 3
  private let masterKeyStore: any IdentityMasterKeyStore
  private let secureStorageService: SecureStorageService
  private let protocolStateStorage: ProtocolStateStorage

  init(
    masterKeyStore: any IdentityMasterKeyStore,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage
  ) {
    self.masterKeyStore = masterKeyStore
    self.secureStorageService = secureStorageService
    self.protocolStateStorage = protocolStateStorage
  }

  func hasStoredIdentity(accountId: UUID) async -> Bool {
    masterKeyStore.hasAnyMasterKeyShare(forAccountId: accountId)
  }

  func saveMasterKey(_ masterKey: Data, forAccountId accountId: UUID) async -> Result<
    Unit, String
  > {
    guard masterKey.count == 32 else {
      return .err("Master key must be 32 bytes, got \(masterKey.count)")
    }
    do {
      let result = try ShamirSecretSharing.splitMasterKey(
        masterKey: masterKey,
        threshold: Self.masterKeyShareThreshold,
        shareCount: Self.masterKeyShareCount
      )
      let saveAuthResult = masterKeyStore.saveShamirAuthKey(result.authKey, forAccountId: accountId)
      guard saveAuthResult.isOk else {
        return .err(saveAuthResult.err() ?? "Failed to save Shamir auth key")
      }

      let saveResult = masterKeyStore.saveMasterKeyShares(result.shares, forAccountId: accountId)
      guard saveResult.isOk else {
        return .err(saveResult.err() ?? "Failed to save master key shares")
      }

      let verifyResult = await loadMasterKey(forAccountId: accountId)
      guard let loadedMasterKey = verifyResult.ok() else {
        return .err("Master key verification failed: \(verifyResult.err() ?? "unknown")")
      }
      guard constantTimeEqual(masterKey, loadedMasterKey) else {
        return .err("Master key verification mismatch")
      }
      return .ok(Unit.value)
    } catch let error as ProtocolError {
      return .err("Failed to split/store master key shares: \(error.message)")
    } catch {
      return .err("Failed to split/store master key shares: \(error.localizedDescription)")
    }
  }

  func loadMasterKey(forAccountId accountId: UUID) async -> Result<Data, String> {
    loadMasterKeySync(forAccountId: accountId)
  }

  func loadMasterKeySync(forAccountId accountId: UUID) -> Result<Data, String> {
    let shares = masterKeyStore.loadMasterKeyShares(forAccountId: accountId)
    guard shares.count >= Int(Self.masterKeyShareThreshold) else {
      return .err("Not enough master key shares found: \(shares.count)")
    }
    guard let authKey = masterKeyStore.loadShamirAuthKey(forAccountId: accountId).ok() else {
      return .err("Failed to load Shamir auth key")
    }
    do {
      let masterKey = try ShamirSecretSharing.reconstructMasterKey(shares: shares, authKey: authKey)
      guard masterKey.count == 32 else {
        return .err("Invalid master key length: expected 32 bytes, got \(masterKey.count)")
      }
      return .ok(masterKey)
    } catch let error as ProtocolError {
      return .err("Failed to reconstruct master key: \(error.message)")
    } catch {
      return .err("Failed to reconstruct master key: \(error.localizedDescription)")
    }
  }

  func deriveSealedStateKey(
    forAccountId accountId: UUID,
    membershipId: UUID
  ) async -> Result<Data, String> {
    guard let masterKey = await loadMasterKey(forAccountId: accountId).ok() else {
      return .err("Master key unavailable for sealed-state key derivation")
    }

    do {
      return .ok(try SealedStateKeyDeriver.deriveKey(masterKey: masterKey, membershipId: membershipId))
    } catch {
      return .err("Opaque root key derivation failed: \(error.localizedDescription)")
    }
  }

  func deleteMasterKey(forAccountId accountId: UUID) async -> Result<Unit, String> {
    let deleteAuthResult = masterKeyStore.deleteShamirAuthKey(forAccountId: accountId)
    if let err = deleteAuthResult.err() {
      return .err("Failed to delete Shamir auth key: \(err)")
    }
    return masterKeyStore.deleteMasterKeyShares(forAccountId: accountId)
  }

  func cleanupMembershipStateWithKeys(
    accountId: UUID,
    connectId: UInt32
  ) async -> Result<Unit, String> {
    let deleteAuthKeyResult = masterKeyStore.deleteShamirAuthKey(forAccountId: accountId)
    if let err = deleteAuthKeyResult.err() {
      return .err("Failed to delete Shamir auth key: \(err)")
    }

    let deleteMasterKeyResult = masterKeyStore.deleteMasterKeyShares(forAccountId: accountId)
    if let err = deleteMasterKeyResult.err() {
      return .err("Failed to delete master key: \(err)")
    }

    let deleteStateResult = await protocolStateStorage.deleteState(
      connectId: String(connectId)
    )
    if let err = deleteStateResult.err() {
      return .err("Failed to delete protocol state: \(err)")
    }

    let clearMembershipResult = await secureStorageService.setMembership(nil)
    if let err = clearMembershipResult.err() {
      return .err("Failed to clear membership: \(err)")
    }

    let clearAccountIdResult = await secureStorageService.setCurrentAccountId(nil)
    if let err = clearAccountIdResult.err() {
      return .err("Failed to clear account ID: \(err)")
    }
    return .ok(Unit.value)
  }

  static func deriveRootKey(from masterKey: Data, accountId: UUID) -> Data {
    let salt = accountId.protobufBytes
    let info: String = "ecliptix-protocol-root-key:v1:\(accountId.uuidString)"
    let infoData: Data = Data(info.utf8)
    let symmetricKey: SymmetricKey = SymmetricKey(data: masterKey)
    let derivedKey: Data = HKDF<SHA512>.deriveKey(
      inputKeyMaterial: symmetricKey,
      salt: salt,
      info: infoData,
      outputByteCount: 32
    ).withUnsafeBytes { Data($0) }
    return derivedKey
  }

  @inline(never)
  private func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    guard lhs.count == rhs.count else { return false }
    return lhs.withUnsafeBytes { lhsPtr in
      rhs.withUnsafeBytes { rhsPtr in
        timingsafe_bcmp(lhsPtr.baseAddress!, rhsPtr.baseAddress!, lhs.count) == 0
      }
    }
  }
}
