// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT

import CryptoKit
import Foundation
import os.log

final class InMemoryPendingRequestManager: PendingRequestManager {

  private var pendingRequests: [String: PendingRequest] = [:]
  private let lock = NSLock()
  private let maxPendingRequests: Int

  init(maxPendingRequests: Int = 100) {
    self.maxPendingRequests = maxPendingRequests
  }

  func addPendingRequest(key: String, request: PendingRequest) {
    lock.lock()
    defer { lock.unlock() }

    if pendingRequests.count >= maxPendingRequests {
      evictOldestRequest()
    }
    pendingRequests[key] = request
  }

  func removePendingRequest(_ key: String) {
    lock.lock()
    defer { lock.unlock() }

    pendingRequests.removeValue(forKey: key)
  }

  func getPendingRequest(_ key: String) -> PendingRequest? {
    lock.lock()
    defer { lock.unlock() }

    return pendingRequests[key]
  }

  func listPendingRequests() -> [PendingRequest] {
    lock.lock()
    defer { lock.unlock() }

    return Array(pendingRequests.values).sorted { $0.createdAt < $1.createdAt }
  }

  private func evictOldestRequest() {
    guard
      let oldestKey =
        pendingRequests
        .min(by: { $0.value.createdAt < $1.value.createdAt })?.key
    else {
      return
    }
    pendingRequests.removeValue(forKey: oldestKey)
  }
}

final class FileSystemStateStorage: NetworkProtocolStateStorage {

  private let baseDirectory: URL
  private let encryptionKey: Data
  private let cachedSymmetricKey: SymmetricKey
  private let fileManager: FileManager

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  init(
    baseDirectory: URL? = nil,
    encryptionKey: Data
  ) {
    self.fileManager = FileManager.default
    self.cachedSymmetricKey = SymmetricKey(data: SHA256.hash(data: encryptionKey))

    if let baseDirectory = baseDirectory {
      self.baseDirectory = baseDirectory
    } else {
      guard
        let appSupport = fileManager.urls(
          for: .applicationSupportDirectory,
          in: .userDomainMask
        ).first
      else {
        self.baseDirectory = fileManager.temporaryDirectory
          .appendingPathComponent("Ecliptix/SessionState")
        self.encryptionKey = encryptionKey

        do {
          try fileManager.createDirectory(
            at: self.baseDirectory,
            withIntermediateDirectories: true
          )
        } catch {
          AppLogger.app.error(
            "PendingRequestManager: failed to create temp directory: \(error.localizedDescription, privacy: .public)"
          )
        }
        return
      }

      self.baseDirectory =
        appSupport
        .appendingPathComponent("Ecliptix/SessionState")
    }

    self.encryptionKey = encryptionKey

    do {
      try fileManager.createDirectory(
        at: self.baseDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      AppLogger.app.error(
        "PendingRequestManager: failed to create session state directory: \(error.localizedDescription, privacy: .public)"
      )
    }
  }

  func saveSessionState(
    _ state: SessionState,
    for connectId: UInt32
  ) async -> Result<Unit, NetworkFailure> {
    let fileURL = baseDirectory.appendingPathComponent("\(connectId).session")

    do {
      let jsonData = try Self.encoder.encode(state)
      let encryptedData = try encrypt(jsonData, connectId: connectId)
      try encryptedData.write(to: fileURL, options: [.atomic, .completeFileProtection])
      return .ok(.value)
    } catch {
      return .err(
        .connectionFailed("Failed to save session state", innerError: error)
      )
    }
  }

  func loadSessionState(
    for connectId: UInt32
  ) async -> Result<SessionState?, NetworkFailure> {
    let fileURL = baseDirectory.appendingPathComponent("\(connectId).session")

    guard fileManager.fileExists(atPath: fileURL.path) else {
      return .ok(nil)
    }

    do {
      let encryptedData = try Data(contentsOf: fileURL)
      let decryptedData = try decrypt(encryptedData, connectId: connectId)
      let state = try Self.decoder.decode(SessionState.self, from: decryptedData)
      return .ok(state)
    } catch {
      return .err(
        .connectionFailed("Failed to load session state", innerError: error)
      )
    }
  }

  func deleteSessionState(
    for connectId: UInt32
  ) async -> Result<Unit, NetworkFailure> {
    let fileURL = baseDirectory.appendingPathComponent("\(connectId).session")

    do {
      if fileManager.fileExists(atPath: fileURL.path) {
        try fileManager.removeItem(at: fileURL)
      }
      return .ok(.value)
    } catch {
      return .err(
        .connectionFailed("Failed to delete session state", innerError: error)
      )
    }
  }

  func deleteAllSessionStates() async -> Result<Unit, NetworkFailure> {
    do {
      let fileURLs = try fileManager.contentsOfDirectory(
        at: baseDirectory,
        includingPropertiesForKeys: nil
      ).filter { $0.pathExtension == "session" }

      for fileURL in fileURLs {
        try fileManager.removeItem(at: fileURL)
      }
      return .ok(.value)
    } catch {
      return .err(
        .connectionFailed("Failed to delete all session states", innerError: error)
      )
    }
  }

  func listSessionStates() async -> Result<[SessionState], NetworkFailure> {
    do {
      let fileURLs = try fileManager.contentsOfDirectory(
        at: baseDirectory,
        includingPropertiesForKeys: nil
      ).filter { $0.pathExtension == "session" }

      var states: [SessionState] = []

      for fileURL in fileURLs {
        let encryptedData = try Data(contentsOf: fileURL)
        let connectId = extractConnectId(from: fileURL)
        let decryptedData = try decrypt(encryptedData, connectId: connectId)
        let state = try Self.decoder.decode(SessionState.self, from: decryptedData)
        states.append(state)
      }

      return .ok(states)
    } catch {
      return .err(
        .connectionFailed("Failed to list session states", innerError: error)
      )
    }
  }

  private func extractConnectId(from fileURL: URL) -> UInt32 {
    let filename = fileURL.deletingPathExtension().lastPathComponent
    return UInt32(filename) ?? 0
  }

  private func buildAAD(version: UInt8, connectId: UInt32) -> Data {
    var aad = Data([version])
    var connectIdLE = connectId.littleEndian
    aad.append(Data(bytes: &connectIdLE, count: 4))
    return aad
  }

  private func encrypt(_ data: Data, connectId: UInt32) throws -> Data {
    let key = cachedSymmetricKey
    let version = SecureStorageConstants.SessionState.version
    let aad = buildAAD(version: version, connectId: connectId)
    let sealedBox = try AES.GCM.seal(data, using: key, authenticating: aad)

    guard let combined = sealedBox.combined else {
      throw NSError(
        domain: "FileSystemStateStorage",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode encrypted payload"]
      )
    }

    var versioned = Data([version])
    versioned.append(combined)
    return versioned
  }

  private func decrypt(_ data: Data, connectId: UInt32) throws -> Data {
    guard !data.isEmpty else {
      throw NSError(
        domain: "FileSystemStateStorage",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Encrypted payload is empty"]
      )
    }

    guard let version = data.first else {
      throw NSError(
        domain: "FileSystemStateStorage",
        code: -3,
        userInfo: [NSLocalizedDescriptionKey: "Encrypted payload has no version byte"]
      )
    }

    guard version == SecureStorageConstants.SessionState.version else {
      throw NSError(
        domain: "FileSystemStateStorage",
        code: -2,
        userInfo: [NSLocalizedDescriptionKey: "Unsupported encryption format version: \(version)"]
      )
    }

    let key = cachedSymmetricKey
    let encryptedPayload = Data(data.dropFirst())
    let aad = buildAAD(version: version, connectId: connectId)
    let sealedBox = try AES.GCM.SealedBox(combined: encryptedPayload)
    return try AES.GCM.open(sealedBox, using: key, authenticating: aad)
  }
}
