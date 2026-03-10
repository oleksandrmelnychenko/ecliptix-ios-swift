// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import CryptoKit
import Foundation

final class ProtocolHandshakeHandler {

  private let security: NetworkProviderSecurity
  private let sessionManager: SecureSessionRuntime

  init(security: NetworkProviderSecurity, sessionManager: SecureSessionRuntime) {
    self.security = security
    self.sessionManager = sessionManager
  }

  func prepareNativeHandshakeEnvelope(
    request: SecrecyChannelRequest,
    certificateData: Data,
    hostname: String
  ) async -> Result<(SecureEnvelope, Data), NetworkFailure> {
    let handshakeResult = await generateHandshakeInit(connectId: request.connectId)
    guard case .ok(let handshakeInit) = handshakeResult else {
      return handshakeResult.propagateErr()
    }

    let envelopeResult = createSecureEnvelope(
      handshakeInit: handshakeInit,
      exchangeType: request.exchangeType,
      connectId: request.connectId
    )
    guard case .ok(let envelope) = envelopeResult else {
      return envelopeResult.propagateErr()
    }
    return .ok((envelope, handshakeInit))
  }

  func processNativeHandshakeResponse(
    responseEnvelope: SecureEnvelope,
    connectId: UInt32
  ) -> Result<Unit, NetworkFailure> {
    let validateResult = validateEnvelopeSignature(envelope: responseEnvelope)
    guard validateResult.isOk else {
      return validateResult.propagateErr()
    }

    let processResult = processServerHandshake(
      payload: responseEnvelope.payload,
      connectId: connectId
    )
    guard processResult.isOk else {
      return processResult.propagateErr()
    }
    return .ok(.value)
  }

  private func generateHandshakeInit(connectId: UInt32) async -> Result<Data, NetworkFailure> {
    let randomResult = await security.platformSecurityProvider.generateSecureRandom(
      byteCount: 32)
    guard case .ok(let clientNonce) = randomResult else {
      return .err(
        .connectionFailed(
          "Failed to generate client nonce",
          innerError: nil
        ))
    }

    var handshakeData = Data()
    handshakeData.append(clientNonce)
    let timestampData = withUnsafeBytes(of: Date().timeIntervalSince1970) { Data($0) }
    handshakeData.append(timestampData)
    return .ok(handshakeData)
  }

  private func createSecureEnvelope(
    handshakeInit: Data,
    exchangeType: PubKeyExchangeType,
    connectId: UInt32
  ) -> Result<SecureEnvelope, NetworkFailure> {
    let metadata: [String: String] = [
      "exchange-type": String(exchangeType.rawValue),
      "connect-id": String(connectId),
      "protocol-version": "1.0",
    ]
    let envelope = SecureEnvelope(
      payload: handshakeInit,
      signature: nil,
      metadata: metadata
    )
    return .ok(envelope)
  }

  private func validateEnvelopeSignature(
    envelope: SecureEnvelope
  ) -> Result<Unit, NetworkFailure> {
    guard let signature = envelope.signature else {
      return .err(.protocolStateMismatch("Missing signature in response envelope"))
    }
    guard let serverPublicKeyHex = envelope.metadata["server-public-key"],
      let serverPublicKey = Data(hexString: serverPublicKeyHex)
    else {
      return .err(.protocolStateMismatch("Missing server public key in metadata"))
    }
    guard !signature.isEmpty,
      signature.count == AppConstants.Crypto.ed25519SignatureBytes
    else {
      return .err(.protocolStateMismatch("Invalid signature size"))
    }
    guard !serverPublicKey.isEmpty else {
      return .err(.protocolStateMismatch("Server public key is empty"))
    }
    do {
      let key = try Curve25519.Signing.PublicKey(rawRepresentation: serverPublicKey)
      let isValid = key.isValidSignature(signature, for: envelope.payload)
      guard isValid else {
        return .err(.protocolStateMismatch("Signature verification failed"))
      }
      return .ok(.value)
    } catch {
      return .err(.protocolStateMismatch("Ed25519 key error: \(error.localizedDescription)"))
    }
  }

  private func processServerHandshake(
    payload: Data,
    connectId: UInt32
  ) -> Result<Unit, NetworkFailure> {
    guard payload.count >= 32 else {
      return .err(.protocolStateMismatch("Invalid handshake response size"))
    }
    _ = payload.prefix(32)
    _ = payload.suffix(from: 32)
    return .ok(.value)
  }
}

struct ProtocolKeyExchange {

  static func deriveSharedSecret(
    privateKey: Data,
    publicKey: Data
  ) -> Result<Data, CryptographyFailure> {
    guard privateKey.count == 32, publicKey.count == 32 else {
      return .err(.invalidBufferSize("Invalid key size for X25519"))
    }
    do {
      let privKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privateKey)
      let pubKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: publicKey)
      let sharedSecret = try privKey.sharedSecretFromKeyAgreement(with: pubKey)
      return .ok(sharedSecret.withUnsafeBytes { Data($0) })
    } catch {
      return .err(.invalidOperation("X25519 key agreement failed"))
    }
  }

  static func deriveSessionKeys(
    sharedSecret: Data,
    salt: Data,
    info: String
  ) -> Result<(encryptionKey: Data, authKey: Data), CryptographyFailure> {
    let hkdf = HKDF<SHA256>.deriveKey(
      inputKeyMaterial: SymmetricKey(data: sharedSecret),
      salt: salt,
      info: Data(info.utf8),
      outputByteCount: 64
    )
    let derivedBytes = hkdf.withUnsafeBytes { Data($0) }
    let encryptionKey = derivedBytes.prefix(32)
    let authKey = derivedBytes.suffix(32)
    return .ok((encryptionKey, authKey))
  }

  static func generateKeyPair() -> Result<
    (privateKey: Data, publicKey: Data), CryptographyFailure
  > {
    let privateKey = Curve25519.KeyAgreement.PrivateKey()
    let publicKey = privateKey.publicKey
    return .ok(
      (
        privateKey: privateKey.rawRepresentation,
        publicKey: publicKey.rawRepresentation
      ))
  }
}

extension Data {

  init?(hexString: String) {
    let string = hexString.replacingOccurrences(of: " ", with: "")
    guard string.count % 2 == 0 else { return nil }
    var data = Data(capacity: string.count / 2)
    var index = string.startIndex
    while index < string.endIndex {
      let nextIndex = string.index(index, offsetBy: 2)
      let byteString = string[index..<nextIndex]
      guard let byte = UInt8(byteString, radix: 16) else { return nil }
      data.append(byte)
      index = nextIndex
    }
    self = data
  }

  var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
