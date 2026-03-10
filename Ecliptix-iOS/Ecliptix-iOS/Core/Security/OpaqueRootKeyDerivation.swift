// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum OpaqueRootKeyDerivation {

  static func deriveRootKey(
    opaqueSessionKey: Data,
    userContext: Data
  ) throws -> Data {
    guard opaqueSessionKey.count == EPPConstants.OPAQUE_SESSION_KEY_LENGTH else {
      throw ProtocolError.invalidInput(
        "OPAQUE session key must be \(EPPConstants.OPAQUE_SESSION_KEY_LENGTH) bytes, got \(opaqueSessionKey.count)"
      )
    }
    guard !userContext.isEmpty else {
      throw ProtocolError.invalidInput("User context cannot be empty")
    }

    var rootKeyBytes = [UInt8](repeating: 0, count: EPPConstants.ROOT_KEY_LENGTH)
    defer { OpaqueNative.secureZero(&rootKeyBytes, rootKeyBytes.count) }

    var errorCode: EPPNative.EppErrorCode = .success
    let resultCode: Int32 = opaqueSessionKey.withUnsafeBytes { sessionKeyBytes in
      userContext.withUnsafeBytes { contextBytes in
        rootKeyBytes.withUnsafeMutableBytes { rootKeyBuffer in
          guard
            let sessionKeyPointer = sessionKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          guard let contextPointer = contextBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          guard let rootKeyPointer = rootKeyBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self)
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.deriveRootKey(
            sessionKeyPointer,
            opaqueSessionKey.count,
            contextPointer,
            userContext.count,
            rootKeyPointer,
            EPPConstants.ROOT_KEY_LENGTH,
            &errorCode
          )
        }
      }
    }
    guard resultCode == EPPNative.EppErrorCode.success.rawValue else {
      throw ProtocolError.from(
        errorCode: errorCode,
        message: "Failed to derive root key from OPAQUE session key"
      )
    }
    return Data(rootKeyBytes)
  }
}
