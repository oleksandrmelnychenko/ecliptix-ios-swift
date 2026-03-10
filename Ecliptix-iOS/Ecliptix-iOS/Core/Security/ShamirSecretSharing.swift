// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Security

struct ShamirSecretSharing {

  static func split(
    secret: Data,
    threshold: UInt8,
    shareCount: UInt8,
    authKey: Data? = nil
  ) throws -> [Data] {
    guard !secret.isEmpty else {
      throw ProtocolError.invalidInput("Secret cannot be empty")
    }
    guard threshold >= 2 else {
      throw ProtocolError.invalidInput("Threshold must be at least 2, got \(threshold)")
    }
    guard shareCount >= threshold else {
      throw ProtocolError.invalidInput(
        "Share count (\(shareCount)) must be >= threshold (\(threshold))")
    }
    guard shareCount <= 255 else {
      throw ProtocolError.invalidInput("Share count cannot exceed 255, got \(shareCount)")
    }
    if let authKey = authKey {
      guard authKey.count == EPPConstants.SEED_LENGTH else {
        throw ProtocolError.invalidInput(
          "Auth key must be \(EPPConstants.SEED_LENGTH) bytes, got \(authKey.count)")
      }
    }

    var sharesBuffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var shareLength: Int = 0
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = secret.withUnsafeBytes { secretRaw in
      guard let secretPointer = secretRaw.bindMemory(to: UInt8.self).baseAddress else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      if let authKey = authKey {
        return authKey.withUnsafeBytes { authRaw in
          guard let authPointer = authRaw.bindMemory(to: UInt8.self).baseAddress else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.shamirSplit(
            secretPointer,
            secret.count,
            threshold,
            shareCount,
            authPointer,
            authKey.count,
            &sharesBuffer,
            &shareLength,
            &errorCode
          )
        }
      } else {
        return EPPNative.shamirSplit(
          secretPointer,
          secret.count,
          threshold,
          shareCount,
          nil,
          0,
          &sharesBuffer,
          &shareLength,
          &errorCode
        )
      }
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(errorCode: errorCode, message: "Failed to split secret into shares")
    }
    guard let sharesData: UnsafeMutablePointer<UInt8> = sharesBuffer.data,
      sharesBuffer.length > 0,
      shareLength > 0
    else {
      throw ProtocolError.bufferTooSmall("Shares buffer is empty")
    }

    let totalLength: Int = sharesBuffer.length
    let expectedLength: Int = shareLength * Int(shareCount)
    guard totalLength == expectedLength else {
      var mutableBuffer: EPPNative.EppBuffer = sharesBuffer
      EPPNative.bufferRelease(&mutableBuffer)
      throw ProtocolError.invalidState(
        "Share buffer size mismatch: expected \(expectedLength), got \(totalLength)")
    }

    var shares: [Data] = []
    shares.reserveCapacity(Int(shareCount))
    for index in 0..<Int(shareCount) {
      let offset: Int = index * shareLength
      let sharePointer: UnsafePointer<UInt8> = UnsafePointer(sharesData.advanced(by: offset))
      let shareData: Data = Data(bytes: sharePointer, count: shareLength)
      shares.append(shareData)
    }

    var mutableBuffer: EPPNative.EppBuffer = sharesBuffer
    EPPNative.bufferRelease(&mutableBuffer)
    return shares
  }

  static func reconstruct(
    shares: [Data],
    authKey: Data? = nil
  ) throws -> Data {
    guard !shares.isEmpty else {
      throw ProtocolError.invalidInput("Shares array cannot be empty")
    }
    guard shares.count >= 2 else {
      throw ProtocolError.invalidInput(
        "At least 2 shares required for reconstruction, got \(shares.count)")
    }

    let shareLength: Int = shares[0].count
    guard shareLength > 0 else {
      throw ProtocolError.invalidInput("Share length cannot be zero")
    }
    for (index, share) in shares.enumerated() {
      guard share.count == shareLength else {
        throw ProtocolError.invalidInput(
          "All shares must have same length. Share 0 has \(shareLength) bytes, share \(index) has \(share.count) bytes"
        )
      }
    }
    if let authKey = authKey {
      guard authKey.count == EPPConstants.SEED_LENGTH else {
        throw ProtocolError.invalidInput(
          "Auth key must be \(EPPConstants.SEED_LENGTH) bytes, got \(authKey.count)")
      }
    }

    var concatenatedShares = Data(capacity: shareLength * shares.count)
    for share in shares {
      concatenatedShares.append(share)
    }
    defer { OpaqueNative.secureZeroData(&concatenatedShares) }

    var secretBuffer: EPPNative.EppBuffer = EPPNative.EppBuffer(data: nil, length: 0)
    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = concatenatedShares.withUnsafeBytes { sharesRaw in
      guard let sharesPointer = sharesRaw.bindMemory(to: UInt8.self).baseAddress else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      if let authKey = authKey {
        return authKey.withUnsafeBytes { authRaw in
          guard let authPointer = authRaw.bindMemory(to: UInt8.self).baseAddress else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.shamirReconstruct(
            sharesPointer,
            concatenatedShares.count,
            shareLength,
            shares.count,
            authPointer,
            authKey.count,
            &secretBuffer,
            &errorCode
          )
        }
      } else {
        return EPPNative.shamirReconstruct(
          sharesPointer,
          concatenatedShares.count,
          shareLength,
          shares.count,
          nil,
          0,
          &secretBuffer,
          &errorCode
        )
      }
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(
        errorCode: errorCode, message: "Failed to reconstruct secret from shares")
    }
    guard let secretData: UnsafeMutablePointer<UInt8> = secretBuffer.data,
      secretBuffer.length > 0
    else {
      throw ProtocolError.bufferTooSmall("Secret buffer is empty")
    }

    let secret: Data = Data(bytes: secretData, count: secretBuffer.length)
    var mutableBuffer: EPPNative.EppBuffer = secretBuffer
    EPPNative.bufferRelease(&mutableBuffer)
    return secret
  }

  struct MasterKeySplitResult {

    let shares: [Data]
    let authKey: Data
  }

  static func splitMasterKey(
    masterKey: Data,
    threshold: UInt8,
    shareCount: UInt8
  ) throws -> MasterKeySplitResult {
    guard masterKey.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidInput(
        "Master key must be \(EPPConstants.SEED_LENGTH) bytes, got \(masterKey.count)")
    }

    var authKey = Data(count: EPPConstants.SEED_LENGTH)
    let status = authKey.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, EPPConstants.SEED_LENGTH, $0.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw ProtocolError.cryptoFailure("Failed to generate random auth key")
    }

    let shares = try split(
      secret: masterKey,
      threshold: threshold,
      shareCount: shareCount,
      authKey: authKey
    )
    guard shares.count == Int(shareCount) else {
      throw ProtocolError.invalidState(
        "Expected \(shareCount) shares, got \(shares.count)")
    }
    return MasterKeySplitResult(shares: shares, authKey: authKey)
  }

  static func reconstructMasterKey(shares: [Data], authKey: Data) throws -> Data {
    let secret: Data = try reconstruct(shares: shares, authKey: authKey)
    guard secret.count == EPPConstants.SEED_LENGTH else {
      throw ProtocolError.invalidState(
        "Reconstructed master key has invalid length: expected \(EPPConstants.SEED_LENGTH), got \(secret.count)"
      )
    }
    return secret
  }
}
