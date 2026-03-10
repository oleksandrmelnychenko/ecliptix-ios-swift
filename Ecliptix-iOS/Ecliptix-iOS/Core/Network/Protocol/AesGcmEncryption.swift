// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

struct AesGcmEncryption {

  private static let nonceSize = 12
  private static let tagSize = 16

  static func encrypt(
    plaintext: Data,
    key: Data,
    associatedData: Data? = nil
  ) -> Result<Data, CryptographyFailure> {
    guard key.count == 32 else {
      return .err(.invalidBufferSize("Key must be 32 bytes for AES-256"))
    }
    do {
      let symmetricKey = SymmetricKey(data: key)
      let nonce = AES.GCM.Nonce()
      let sealedBox: AES.GCM.SealedBox
      if let associatedData = associatedData {
        sealedBox = try AES.GCM.seal(
          plaintext,
          using: symmetricKey,
          nonce: nonce,
          authenticating: associatedData
        )
      } else {
        sealedBox = try AES.GCM.seal(
          plaintext,
          using: symmetricKey,
          nonce: nonce
        )
      }

      var result = Data(capacity: nonceSize + plaintext.count + tagSize)
      result.append(contentsOf: nonce.withUnsafeBytes { Data($0) })
      result.append(sealedBox.ciphertext)
      result.append(sealedBox.tag)
      return .ok(result)
    } catch {
      return .err(
        .initializationFailed("AES-GCM encryption failed: \(error.localizedDescription)"))
    }
  }

  static func decrypt(
    ciphertext: Data,
    key: Data,
    associatedData: Data? = nil
  ) -> Result<Data, CryptographyFailure> {
    guard key.count == 32 else {
      return .err(.invalidBufferSize("Key must be 32 bytes for AES-256"))
    }
    guard ciphertext.count > nonceSize + tagSize else {
      return .err(.bufferTooSmall("Ciphertext too small"))
    }
    do {
      let symmetricKey = SymmetricKey(data: key)
      let nonceData = ciphertext.prefix(nonceSize)
      let nonce = try AES.GCM.Nonce(data: nonceData)
      let actualCiphertext = ciphertext.dropFirst(nonceSize).dropLast(tagSize)
      let tag = ciphertext.suffix(tagSize)
      let sealedBox: AES.GCM.SealedBox
      if let associatedData = associatedData {
        sealedBox = try AES.GCM.SealedBox(
          nonce: nonce,
          ciphertext: actualCiphertext,
          tag: tag
        )
        let plaintext = try AES.GCM.open(
          sealedBox,
          using: symmetricKey,
          authenticating: associatedData
        )
        return .ok(plaintext)
      } else {
        sealedBox = try AES.GCM.SealedBox(
          nonce: nonce,
          ciphertext: actualCiphertext,
          tag: tag
        )
        let plaintext = try AES.GCM.open(sealedBox, using: symmetricKey)
        return .ok(plaintext)
      }
    } catch {
      return .err(
        .initializationFailed("AES-GCM decryption failed: \(error.localizedDescription)"))
    }
  }

  static func encryptWithAad(
    plaintext: Data,
    key: Data,
    aad: Data
  ) -> Result<Data, CryptographyFailure> {
    encrypt(plaintext: plaintext, key: key, associatedData: aad)
  }

  static func decryptWithAad(
    ciphertext: Data,
    key: Data,
    aad: Data
  ) -> Result<Data, CryptographyFailure> {
    decrypt(ciphertext: ciphertext, key: key, associatedData: aad)
  }
}

struct ProtocolMessageEncryption {

  static func encryptMessage(
    message: Data,
    sessionKey: Data,
    messageId: UInt64,
    senderId: UUID
  ) -> Result<Data, CryptographyFailure> {
    var aad = Data(capacity: 24)
    aad.append(contentsOf: withUnsafeBytes(of: messageId) { Data($0) })
    aad.append(senderId.protobufBytes)
    return AesGcmEncryption.encryptWithAad(
      plaintext: message,
      key: sessionKey,
      aad: aad
    )
  }

  static func decryptMessage(
    ciphertext: Data,
    sessionKey: Data,
    messageId: UInt64,
    senderId: UUID
  ) -> Result<Data, CryptographyFailure> {
    var aad = Data(capacity: 24)
    aad.append(contentsOf: withUnsafeBytes(of: messageId) { Data($0) })
    aad.append(senderId.protobufBytes)
    return AesGcmEncryption.decryptWithAad(
      ciphertext: ciphertext,
      key: sessionKey,
      aad: aad
    )
  }
}
