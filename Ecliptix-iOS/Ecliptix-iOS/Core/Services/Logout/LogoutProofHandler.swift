// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class LogoutProofHandler {

  private let identityService: IdentityService
  private let secureStorage: SecureStorageService

  init(
    identityService: IdentityService,
    secureStorage: SecureStorageService
  ) {
    self.identityService = identityService
    self.secureStorage = secureStorage
  }

  func generateLogoutHmacProof(
    request: AuthenticatedLogoutRequest,
    accountId: UUID
  ) async -> Result<Data, LogoutFailure> {
    let masterKeyResult = await identityService.loadMasterKey(forAccountId: accountId)
    guard let masterKey = masterKeyResult.ok() else {
      let errorMessage =
        "\(AppConstants.LogoutProof.masterKeyRetrievalFailedPrefix) \(masterKeyResult.err() ?? "")"
      return .err(.cryptographicOperationFailed(errorMessage))
    }

    var hmacKey = LogoutKeyDerivation.deriveLogoutHmacKey(masterKey: masterKey)
    defer { OpaqueNative.secureZeroData(&hmacKey) }

    let canonical =
      "\(AppConstants.Logout.canonicalPrefix):\(request.membershipID.base64EncodedString()):\(request.timestamp.seconds):\(canonicalScopeName(request.scope)):\(request.logoutReason.rawValue)"
    let canonicalData = Data(canonical.utf8)
    let proof = LogoutKeyDerivation.computeHmac(key: hmacKey, data: canonicalData)
    return .ok(proof)
  }

  func verifyRevocationProof(
    proofData: Data,
    membershipId: UUID,
    accountId: UUID,
    connectId: UInt32,
    serverTimestamp: Int64
  ) async -> Result<Unit, LogoutFailure> {
    guard !proofData.isEmpty else {
      return .err(
        .invalidRevocationProof(AppConstants.LogoutProof.serverDidNotProvideRevocationProof))
    }

    let parseResult = parseRevocationProof(proofData)
    guard let parsed = parseResult.ok() else {
      return parseResult.propagateErr()
    }

    let masterKeyResult = await identityService.loadMasterKey(forAccountId: accountId)
    guard let masterKey = masterKeyResult.ok() else {
      let errorMessage =
        "\(AppConstants.LogoutProof.masterKeyRetrievalFailedPrefix) \(masterKeyResult.err() ?? "")"
      return .err(.cryptographicOperationFailed(errorMessage))
    }

    var proofKey = LogoutKeyDerivation.deriveLogoutProofKey(masterKey: masterKey)
    defer { OpaqueNative.secureZeroData(&proofKey) }

    let canonicalData = buildCanonicalProofData(
      membershipId: membershipId,
      connectId: connectId,
      serverTimestamp: serverTimestamp,
      parsed: parsed
    )
    guard
      LogoutKeyDerivation.verifyHmac(
        key: proofKey, data: canonicalData, expectedHmac: parsed.hmacProof)
    else {
      return .err(
        .invalidRevocationProof(
          AppConstants.LogoutProof.serverRevocationProofHmacVerificationFailed))
    }

    let storeResult = await secureStorage.saveRevocationProof(proofData, for: membershipId)
    if storeResult.isErr {
      AppLogger.auth.warning(
        "[LOGOUT-PROOF] Failed to store revocation proof: \(storeResult.err() ?? "", privacy: .public)"
      )
    }
    return .ok(.value)
  }

  func hasRevocationProof(membershipId: UUID) async -> Bool {
    await secureStorage.hasRevocationProof(for: membershipId)
  }

  func clearRevocationProof(membershipId: UUID) async {
    let result = await secureStorage.consumeRevocationProof(for: membershipId)
    if result.isErr {
      AppLogger.security.warning(
        "LogoutProofHandler: failed to consume revocation proof for membershipId=\(membershipId.uuidString, privacy: .public), error=\(result.err() ?? "", privacy: .public)"
      )
    }
  }

  private struct ParsedProof {

    let nonce: Data
    let fingerprintLength: Int
    let fingerprint: Data
    let hmacProof: Data
  }

  private func parseRevocationProof(_ proofData: Data) -> Result<ParsedProof, LogoutFailure> {
    let proofVersionHmac: UInt8 = 1
    let nonceSize = 16
    let hmacSize = 32
    let maxFingerprintSize = 64
    let minSize = 1 + 4 + nonceSize + 4 + hmacSize
    guard proofData.count >= minSize else {
      return .err(
        .invalidRevocationProof(
          "Revocation proof too small: \(proofData.count) bytes"
        ))
    }

    var offset = 0
    let version = proofData[offset]
    offset += 1
    guard version == proofVersionHmac else {
      return .err(
        .invalidRevocationProof(
          "\(AppConstants.LogoutProof.unsupportedRevocationProofVersion) \(version)"))
    }

    let nonceLength = proofData.readInt32(at: offset)
    offset += 4
    guard nonceLength == nonceSize else {
      return .err(
        .invalidRevocationProof("\(AppConstants.LogoutProof.invalidNonceLength) \(nonceLength)"))
    }
    guard offset + nonceLength <= proofData.count else {
      return .err(
        .invalidRevocationProof(AppConstants.LogoutProof.revocationProofTruncatedWhileReadingNonce))
    }

    let nonce = proofData.subdata(in: offset..<(offset + nonceLength))
    offset += nonceLength
    let fingerprintLength = proofData.readInt32(at: offset)
    offset += 4
    guard fingerprintLength >= 0, fingerprintLength <= maxFingerprintSize else {
      return .err(
        .invalidRevocationProof(
          "\(AppConstants.LogoutProof.invalidFingerprintLength) \(fingerprintLength)"))
    }

    var fingerprint = Data()
    if fingerprintLength > 0 {
      guard offset + fingerprintLength <= proofData.count else {
        return .err(
          .invalidRevocationProof(
            AppConstants.LogoutProof.revocationProofTruncatedWhileReadingFingerprint))
      }
      fingerprint = proofData.subdata(in: offset..<(offset + fingerprintLength))
      offset += fingerprintLength
    }

    let remaining = proofData.count - offset
    guard remaining == hmacSize else {
      return .err(
        .invalidRevocationProof("\(AppConstants.LogoutProof.invalidHmacLength) \(remaining)"))
    }

    let hmacProof = proofData.subdata(in: offset..<(offset + hmacSize))
    return .ok(
      ParsedProof(
        nonce: nonce,
        fingerprintLength: fingerprintLength,
        fingerprint: fingerprint,
        hmacProof: hmacProof
      ))
  }

  private func buildCanonicalProofData(
    membershipId: UUID,
    connectId: UInt32,
    serverTimestamp: Int64,
    parsed: ParsedProof
  ) -> Data {
    var data = Data(capacity: 16 + 4 + 8 + 4 + parsed.fingerprintLength + parsed.nonce.count)
    data.append(membershipId.protobufBytes)
    withUnsafeBytes(of: connectId.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: serverTimestamp.littleEndian) { data.append(contentsOf: $0) }
    withUnsafeBytes(of: Int32(parsed.fingerprintLength).littleEndian) {
      data.append(contentsOf: $0)
    }
    if parsed.fingerprintLength > 0 {
      data.append(parsed.fingerprint)
    }
    data.append(parsed.nonce)
    return data
  }

  private func canonicalScopeName(_ scope: LogoutScope) -> String {
    switch scope {
    case .thisDevice:
      return AppConstants.Logout.scopeThisDevice
    case .allDevices:
      return AppConstants.Logout.scopeAllDevices
    default:
      return AppConstants.Logout.scopeUnspecified
    }
  }
}

extension Data {

  fileprivate func readInt32(at offset: Int) -> Int {
    guard offset + 4 <= count else { return 0 }
    let value = subdata(in: offset..<(offset + 4))
      .withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
    return Int(value)
  }
}
