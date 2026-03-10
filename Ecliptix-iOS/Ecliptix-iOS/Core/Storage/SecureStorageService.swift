// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation
import Security
import os

final class SecureStorageService {
  static let shared: SecureStorageService = SecureStorageService()
  private let fileManager: FileManager = FileManager.default
  private let encryptedSettingsFileName: String = "app-instance-settings.enc"
  private let lock: NSLock = NSLock()
  private static let settingsEncoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = .prettyPrinted
    return e
  }()
  private static let settingsDecoder = JSONDecoder()
  private var cachedSettings: ApplicationInstanceSettings?
  private var cachedEncryptionKey: SymmetricKey?
  private lazy var storageDirectory: URL = {
    let appSupport: URL =
      fileManager.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
      ?? fileManager.temporaryDirectory.appendingPathComponent("Ecliptix")
    var ecliptixDir: URL = appSupport.appendingPathComponent("Ecliptix", isDirectory: true)
    if !fileManager.fileExists(atPath: ecliptixDir.path) {
      do {
        try fileManager.createDirectory(at: ecliptixDir, withIntermediateDirectories: true)
      } catch {
        AppLogger.security.error(
          "SecureStorage: failed to create storage directory: \(error.localizedDescription, privacy: .public)"
        )
      }
    }

    var resourceValues = URLResourceValues()
    resourceValues.isExcludedFromBackup = true
    do {
      try ecliptixDir.setResourceValues(resourceValues)
    } catch {
      AppLogger.security.error(
        "SecureStorage: failed to exclude directory from backup: \(error.localizedDescription, privacy: .public)"
      )
    }
    return ecliptixDir
  }()

  private init() {}
  private var encryptedSettingsFileURL: URL {
    storageDirectory.appendingPathComponent(encryptedSettingsFileName)
  }

  private var revocationProofsDirectory: URL {
    let dir: URL = storageDirectory.appendingPathComponent("RevocationProofs", isDirectory: true)
    if !fileManager.fileExists(atPath: dir.path) {
      do {
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
      } catch {
        AppLogger.security.error(
          "SecureStorage: failed to create revocation proofs directory: \(error.localizedDescription, privacy: .public)"
        )
      }
    }
    return dir
  }

  private func revocationProofFilePath(for membershipId: UUID) -> URL {
    let hash: String = SHA256.hash(data: Data(membershipId.uuidString.lowercased().utf8))
      .compactMap { String(format: "%02x", $0) }
      .joined()
      .prefix(SecureStorageConstants.Identity.revocationProofHashPrefixLength)
      .lowercased()
    return revocationProofsDirectory.appendingPathComponent("\(hash).proof")
  }

  private func getOrCreateEncryptionKey() -> SymmetricKey? {
    if let cached = cachedEncryptionKey {
      return cached
    }

    let keyName: String = AppConstants.Keychain.settingsEncryptionKeyName
    let loadQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConstants.Keychain.serviceName,
      kSecAttrAccount as String: keyName,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
      kSecAttrSynchronizable as String: false,
    ]
    var result: AnyObject?
    let loadStatus: OSStatus = SecItemCopyMatching(loadQuery as CFDictionary, &result)
    if loadStatus == errSecSuccess, let keyData = result as? Data,
      keyData.count == SecureStorageConstants.Encryption.keySize
    {
      let key: SymmetricKey = SymmetricKey(data: keyData)
      cachedEncryptionKey = key
      return key
    }
    if loadStatus == errSecSuccess {
      AppLogger.security.error(
        "SecureStorageService: encryption key has unexpected length; refusing to replace it implicitly"
      )
      return nil
    }
    if loadStatus != errSecItemNotFound {
      AppLogger.security.error(
        "SecureStorageService: encryption key load failed with status=\(loadStatus, privacy: .public); refusing to generate a replacement key implicitly"
      )
      return nil
    }

    var bytes: [UInt8] = [UInt8](repeating: 0, count: SecureStorageConstants.Encryption.keySize)
    let genStatus: OSStatus = SecRandomCopyBytes(
      kSecRandomDefault, SecureStorageConstants.Encryption.keySize, &bytes)
    guard genStatus == errSecSuccess else {
      return nil
    }

    let newKeyData: Data = Data(bytes)
    let deleteQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConstants.Keychain.serviceName,
      kSecAttrAccount as String: keyName,
    ]
    SecItemDelete(deleteQuery as CFDictionary)
    let addQuery: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: AppConstants.Keychain.serviceName,
      kSecAttrAccount as String: keyName,
      kSecValueData as String: newKeyData,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
      kSecAttrSynchronizable as String: false,
    ]
    let addStatus: OSStatus = SecItemAdd(addQuery as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      return nil
    }

    let key: SymmetricKey = SymmetricKey(data: newKeyData)
    cachedEncryptionKey = key
    return key
  }

  private func encryptData(_ plaintext: Data, using key: SymmetricKey) -> Data? {
    do {
      let sealedBox = try AES.GCM.seal(plaintext, using: key)
      guard let combined = sealedBox.combined else {
        AppLogger.security.error("SecureStorageService: AES-GCM seal produced no combined data")
        return nil
      }

      var versioned: Data = Data([SecureStorageConstants.Settings.versionByte])
      versioned.append(combined)
      return versioned
    } catch {
      AppLogger.security.error(
        "SecureStorageService: AES-GCM encryption failed, error=\(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }

  private func decryptData(_ data: Data, using key: SymmetricKey) -> Data? {
    guard !data.isEmpty else { return nil }
    if data.first == SecureStorageConstants.Settings.versionByte {
      let encryptedPayload: Data = Data(data.dropFirst())
      do {
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedPayload)
        return try AES.GCM.open(sealedBox, using: key)
      } catch {
        AppLogger.security.error(
          "SecureStorageService: AES-GCM decryption failed, error=\(error.localizedDescription, privacy: .public)"
        )
        return nil
      }
    }
    return nil
  }

  func initApplicationInstanceSettings(
    defaultCulture: String = "en-US"
  ) async -> Result<InstanceSettingsResult, String> {
    let result: Result<InstanceSettingsResult, String> = lock.withLock {
      let canonicalDeviceId = NetworkConfiguration.default.deviceId
      let canonicalAppInstanceId = NetworkConfiguration.default.appInstanceId
      if let cached = cachedSettings {
        if cached.deviceId == canonicalDeviceId,
          cached.appInstanceId == canonicalAppInstanceId
        {
          return .ok((cached, false))
        }

        let normalized = ApplicationInstanceSettings(
          deviceId: canonicalDeviceId,
          appInstanceId: canonicalAppInstanceId,
          culture: cached.culture,
          membership: cached.membership,
          currentAccountId: cached.currentAccountId,
          registrationCheckpoint: cached.registrationCheckpoint
        )
        let saveResult = persistSettingsToDisk(normalized)
        guard saveResult.isOk else {
          return .err("Failed to normalize cached settings IDs: \(saveResult.err() ?? "unknown")")
        }
        cachedSettings = normalized
        return .ok((normalized, false))
      }

      let loadResult = loadSettings()
      if let existingSettings = loadResult.ok() {
        if existingSettings.deviceId == canonicalDeviceId,
          existingSettings.appInstanceId == canonicalAppInstanceId
        {
          cachedSettings = existingSettings
          return .ok((existingSettings, false))
        }

        let normalized = ApplicationInstanceSettings(
          deviceId: canonicalDeviceId,
          appInstanceId: canonicalAppInstanceId,
          culture: existingSettings.culture,
          membership: existingSettings.membership,
          currentAccountId: existingSettings.currentAccountId,
          registrationCheckpoint: existingSettings.registrationCheckpoint
        )
        let saveResult = persistSettingsToDisk(normalized)
        guard saveResult.isOk else {
          return .err("Failed to normalize settings IDs: \(saveResult.err() ?? "unknown")")
        }
        cachedSettings = normalized
        return .ok((normalized, false))
      }

      let newSettings = ApplicationInstanceSettings(
        deviceId: canonicalDeviceId,
        appInstanceId: canonicalAppInstanceId,
        culture: defaultCulture,
        membership: nil,
        currentAccountId: nil,
        registrationCheckpoint: nil
      )
      let saveResult = persistSettingsToDisk(newSettings)
      guard saveResult.isOk else {
        return .err("Failed to save new settings: \(saveResult.err() ?? "unknown")")
      }
      cachedSettings = newSettings
      return .ok((newSettings, true))
    }
    return result
  }

  func loadSettings() -> Result<ApplicationInstanceSettings, String> {
    if fileManager.fileExists(atPath: encryptedSettingsFileURL.path) {
      return loadEncryptedSettings()
    }
    return .err("Settings file does not exist")
  }

  private func loadEncryptedSettings() -> Result<ApplicationInstanceSettings, String> {
    guard let key = getOrCreateEncryptionKey() else {
      return .err("Failed to obtain encryption key")
    }
    do {
      let encryptedData: Data = try Data(contentsOf: encryptedSettingsFileURL)
      guard let decryptedData = decryptData(encryptedData, using: key) else {
        return .err("Failed to decrypt settings file")
      }

      let settings: ApplicationInstanceSettings = try Self.settingsDecoder.decode(
        ApplicationInstanceSettings.self,
        from: decryptedData
      )
      return .ok(settings)
    } catch {
      return .err("Failed to load encrypted settings: \(error.localizedDescription)")
    }
  }

  private func persistSettingsToDisk(_ settings: ApplicationInstanceSettings) -> Result<
    Unit, String
  > {
    guard let key = getOrCreateEncryptionKey() else {
      return .err("Failed to obtain encryption key")
    }
    do {
      let jsonData: Data = try Self.settingsEncoder.encode(settings)
      guard let encryptedData = encryptData(jsonData, using: key) else {
        return .err("Failed to encrypt settings data")
      }
      try encryptedData.write(to: encryptedSettingsFileURL, options: .atomic)
      return .ok(Unit.value)
    } catch {
      return .err("Failed to save settings: \(error.localizedDescription)")
    }
  }

  func saveSettings(_ settings: ApplicationInstanceSettings) -> Result<Unit, String> {
    let result = persistSettingsToDisk(settings)
    if result.isOk {
      lock.withLock {
        cachedSettings = settings
      }
    }
    return result
  }

  private func resolveSettings() -> Result<ApplicationInstanceSettings, String> {
    lock.withLock {
      if let settings = cachedSettings {
        return .ok(settings)
      }

      let loaded = loadSettings()
      if let settings = loaded.ok() {
        cachedSettings = settings
        return .ok(settings)
      }
      AppLogger.security.warning(
        "SecureStorageService: resolveSettings loadSettings failed (\(loaded.err() ?? "unknown", privacy: .public)), auto-creating default settings"
      )
      let newSettings = ApplicationInstanceSettings(
        deviceId: NetworkConfiguration.default.deviceId,
        appInstanceId: NetworkConfiguration.default.appInstanceId,
        culture: "en-US",
        membership: nil,
        currentAccountId: nil,
        registrationCheckpoint: nil
      )
      let saveResult = persistSettingsToDisk(newSettings)
      guard saveResult.isOk else {
        return .err(
          "Settings not initialized and auto-create failed: \(saveResult.err() ?? "unknown")")
      }
      cachedSettings = newSettings
      return .ok(newSettings)
    }
  }

  func setMembership(_ membership: Membership?) async -> Result<Unit, String> {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.membership = membership
    if membership == nil {
      settings.registrationCheckpoint = nil
    }
    return saveSettings(settings)
  }

  func setCurrentAccountId(_ accountId: UUID?) async -> Result<Unit, String> {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.currentAccountId = accountId
    if accountId == nil && settings.membership == nil {
      settings.registrationCheckpoint = nil
    }
    return saveSettings(settings)
  }

  func setMembershipAndAccountId(
    membership: Membership?,
    accountId: UUID?
  ) async -> Result<Unit, String> {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.membership = membership
    settings.currentAccountId = accountId
    if membership == nil {
      settings.registrationCheckpoint = nil
    }
    return saveSettings(settings)
  }

  func setRegistrationState(
    membership: Membership?,
    accountId: UUID?,
    checkpoint: RegistrationCheckpoint?
  ) async -> Result<Unit, String> {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.membership = membership
    settings.currentAccountId = accountId
    settings.registrationCheckpoint = checkpoint
    if membership == nil && accountId == nil {
      settings.registrationCheckpoint = nil
    }
    return saveSettings(settings)
  }

  func setRegistrationCheckpoint(_ checkpoint: RegistrationCheckpoint?) async -> Result<
    Unit, String
  > {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.registrationCheckpoint = checkpoint
    return saveSettings(settings)
  }

  func setCulture(_ culture: String) async -> Result<Unit, String> {
    let resolved = resolveSettings()
    guard var settings = resolved.ok() else {
      return .err(resolved.err() ?? "unknown")
    }
    settings.culture = culture
    return saveSettings(settings)
  }

  var settings: ApplicationInstanceSettings? {
    lock.lock()
    defer { lock.unlock() }

    return cachedSettings
  }

  func clearCaches() {
    lock.withLock {
      cachedSettings = nil
      cachedEncryptionKey = nil
    }
  }

  func saveRevocationProof(_ proof: Data, for membershipId: UUID) async -> Result<Unit, String> {
    guard !proof.isEmpty else {
      return .err("Revocation proof cannot be empty")
    }
    guard let key = getOrCreateEncryptionKey() else {
      return .err("Failed to obtain encryption key")
    }
    return lock.withLock {
      guard let encrypted = encryptData(proof, using: key) else {
        return .err("Failed to encrypt revocation proof")
      }

      let fileURL: URL = revocationProofFilePath(for: membershipId)
      do {
        try encrypted.write(to: fileURL, options: .atomic)
        return .ok(Unit.value)
      } catch {
        return .err("Failed to save revocation proof: \(error.localizedDescription)")
      }
    }
  }

  func hasRevocationProof(for membershipId: UUID) async -> Bool {
    lock.withLock {
      let fileURL: URL = revocationProofFilePath(for: membershipId)
      return fileManager.fileExists(atPath: fileURL.path)
    }
  }

  func consumeRevocationProof(for membershipId: UUID) async -> Result<Unit, String> {
    lock.withLock {
      let fileURL: URL = revocationProofFilePath(for: membershipId)
      guard fileManager.fileExists(atPath: fileURL.path) else {
        return .ok(Unit.value)
      }
      do {
        try fileManager.removeItem(at: fileURL)
        return .ok(Unit.value)
      } catch {
        return .err("Failed to consume revocation proof: \(error.localizedDescription)")
      }
    }
  }

  func loadRevocationProof(for membershipId: UUID) async -> Result<Data, String> {
    guard let key = getOrCreateEncryptionKey() else {
      return .err("Failed to obtain encryption key")
    }
    return lock.withLock {
      let fileURL: URL = revocationProofFilePath(for: membershipId)
      guard fileManager.fileExists(atPath: fileURL.path) else {
        return .err("Revocation proof not found")
      }
      do {
        let encryptedData: Data = try Data(contentsOf: fileURL)
        guard let decrypted = decryptData(encryptedData, using: key) else {
          return .err("Failed to decrypt revocation proof")
        }
        return .ok(decrypted)
      } catch {
        return .err(
          "Failed to load revocation proof: \(error.localizedDescription)")
      }
    }
  }
}
