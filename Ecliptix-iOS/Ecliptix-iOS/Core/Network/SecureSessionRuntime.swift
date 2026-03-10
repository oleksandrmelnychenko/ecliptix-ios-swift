// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class SecureSessionRuntime: @unchecked Sendable {

  private var identities: [UInt32: EcliptixIdentityKeys] = [:]
  private var sessions: [UInt32: NativeProtocolSession] = [:]
  private var serverPreKeyBundles: [UInt32: Data] = [:]
  private var serverPublicKeys: [UInt32: Data] = [:]
  private var serverNonces: [UInt32: Data] = [:]
  private var handshakeInitiators: [UInt32: HandshakeInitiator] = [:]
  private let lock = NSLock()

  func get(connectId: UInt32) -> Result<NativeProtocolSession, ProtocolFailure> {
    lock.withLock {
      guard let session = sessions[connectId] else {
        return .err(.generic("Session not found for connectId \(connectId)"))
      }
      return .ok(session)
    }
  }

  func store(connectId: UInt32, session: NativeProtocolSession) {
    lock.withLock {
      sessions[connectId] = session
    }
  }

  func remove(connectId: UInt32) {
    lock.withLock {
      sessions.removeValue(forKey: connectId)?.dispose()
      identities.removeValue(forKey: connectId)?.dispose()
      handshakeInitiators.removeValue(forKey: connectId)?.dispose()
      serverPreKeyBundles.removeValue(forKey: connectId)
      serverPublicKeys.removeValue(forKey: connectId)
      serverNonces.removeValue(forKey: connectId)
    }
  }

  func invalidateSession(connectId: UInt32) {
    lock.withLock {
      sessions.removeValue(forKey: connectId)?.dispose()
      handshakeInitiators.removeValue(forKey: connectId)?.dispose()
      serverPreKeyBundles.removeValue(forKey: connectId)
      serverNonces.removeValue(forKey: connectId)
    }
  }

  func disposeAll() {
    lock.withLock {
      sessions.values.forEach { $0.dispose() }
      sessions.removeAll()
      identities.values.forEach { $0.dispose() }
      identities.removeAll()
      handshakeInitiators.values.forEach { $0.dispose() }
      handshakeInitiators.removeAll()
      serverPreKeyBundles.removeAll()
      serverPublicKeys.removeAll()
      serverNonces.removeAll()
    }
  }

  func clearServerPreKeyBundle(connectId: UInt32) {
    lock.withLock {
      serverPreKeyBundles.removeValue(forKey: connectId)
    }
  }

  func clearServerPublicKey(connectId: UInt32) {
    lock.withLock {
      serverPublicKeys.removeValue(forKey: connectId)
    }
  }

  func clearHandshakeInitiator(connectId: UInt32) {
    lock.withLock {
      handshakeInitiators.removeValue(forKey: connectId)?.dispose()
    }
  }

  func singleActiveConnectId() -> UInt32? {
    lock.withLock {
      guard sessions.count == 1, let onlyConnectId = sessions.keys.first else {
        return nil
      }
      return onlyConnectId
    }
  }

  func storeIdentity(connectId: UInt32, identity: EcliptixIdentityKeys) {
    lock.withLock {
      identities[connectId] = identity
    }
  }

  func storeServerPreKeyBundle(connectId: UInt32, bundle: Data) {
    lock.withLock {
      serverPreKeyBundles[connectId] = bundle
    }
  }

  func storeServerPublicKey(connectId: UInt32, publicKey: Data) {
    lock.withLock {
      serverPublicKeys[connectId] = publicKey
    }
  }

  func getServerPublicKey(connectId: UInt32) -> Result<Data, ProtocolFailure> {
    lock.withLock {
      guard let serverPublicKey = serverPublicKeys[connectId] else {
        return .err(.generic("Server public key not found for connectId \(connectId)"))
      }
      return .ok(serverPublicKey)
    }
  }

  func storeServerNonce(connectId: UInt32, nonce: Data) {
    lock.withLock {
      serverNonces[connectId] = nonce
    }
  }

  func clearServerNonce(connectId: UInt32) {
    lock.withLock {
      serverNonces.removeValue(forKey: connectId)
    }
  }

  func getIdentity(connectId: UInt32) -> Result<EcliptixIdentityKeys, ProtocolFailure> {
    lock.withLock {
      guard let identity = identities[connectId] else {
        return .err(.generic("Identity not found for connectId \(connectId)"))
      }
      return .ok(identity)
    }
  }

  func storeHandshakeInitiator(connectId: UInt32, initiator: HandshakeInitiator) {
    lock.withLock {
      handshakeInitiators[connectId] = initiator
    }
  }

  func getHandshakeInitiator(connectId: UInt32) -> Result<HandshakeInitiator, ProtocolFailure> {
    lock.withLock {
      guard let initiator = handshakeInitiators[connectId] else {
        return .err(.generic("Handshake initiator not found for connectId \(connectId)"))
      }
      return .ok(initiator)
    }
  }

  func removeHandshakeInitiator(connectId: UInt32) {
    lock.withLock {
      handshakeInitiators.removeValue(forKey: connectId)
    }
  }
}
