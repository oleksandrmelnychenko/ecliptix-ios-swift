// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

enum LogoutKeyDerivation {

  private static let keySize = 32
  private static let hmacSize = 32

  static func deriveLogoutHmacKey(masterKey: Data) -> Data {
    let info = Data(AppConstants.Logout.hmacInfo.utf8)
    let derived = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: masterKey),
      salt: Data(),
      info: info,
      outputByteCount: keySize
    )
    return derived.withUnsafeBytes { Data($0) }
  }

  static func deriveLogoutProofKey(masterKey: Data) -> Data {
    let info = Data(AppConstants.Logout.proofInfo.utf8)
    let derived = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: masterKey),
      salt: Data(),
      info: info,
      outputByteCount: keySize
    )
    return derived.withUnsafeBytes { Data($0) }
  }

  static func computeHmac(key: Data, data: Data) -> Data {
    let code = HMAC<SHA256>.authenticationCode(
      for: data,
      using: SymmetricKey(data: key)
    )
    return Data(code)
  }

  static func verifyHmac(key: Data, data: Data, expectedHmac: Data) -> Bool {
    guard expectedHmac.count == hmacSize else {
      return false
    }

    let computed = computeHmac(key: key, data: data)
    return constantTimeEqual(computed, expectedHmac)
  }

  private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
    lhs.withUnsafeBytes { lhsRaw in
      rhs.withUnsafeBytes { rhsRaw in
        let lhsPtr = lhsRaw.bindMemory(to: UInt8.self)
        let rhsPtr = rhsRaw.bindMemory(to: UInt8.self)
        let length = max(lhsPtr.count, rhsPtr.count)
        var diff: UInt8 = 0
        for i in 0..<length {
          let a: UInt8 = i < lhsPtr.count ? lhsPtr[i] : 0
          let b: UInt8 = i < rhsPtr.count ? rhsPtr[i] : 0
          diff |= a ^ b
        }
        diff |= UInt8(truncatingIfNeeded: lhsPtr.count ^ rhsPtr.count)
        return diff == 0
      }
    }
  }
  #if DEBUG
    static let _selfTest: Void = {
      var key = Data(repeating: 0, count: 32)
      for i in 0..<32 { key[i] = UInt8(i) }
      let testData = Data("logout-self-test".utf8)
      let validHmac = computeHmac(key: key, data: testData)
      precondition(
        verifyHmac(key: key, data: testData, expectedHmac: validHmac),
        "LogoutKeyDerivation self-test failed: expected HMAC to verify"
      )
      var tampered = validHmac
      tampered[0] ^= 0xFF
      precondition(
        !verifyHmac(key: key, data: testData, expectedHmac: tampered),
        "LogoutKeyDerivation self-test failed: tampered HMAC verified"
      )
      OpaqueNative.secureZeroData(&key)
    }()
  #endif
}
