// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtocolC
import Foundation

final class HandshakeInitiator: @unchecked Sendable {

  private let handle: EPPNative.EppHandle
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  private init(handle: EPPNative.EppHandle) {
    self.handle = handle
  }

  static func start(
    identity: EcliptixIdentityKeys,
    peerPrekeyBundle: Data,
    config: EPPNative.EppSessionConfig
  ) throws -> (handshakeInit: Data, initiator: HandshakeInitiator) {
    guard !peerPrekeyBundle.isEmpty else {
      throw ProtocolError.invalidInput("Peer prekey bundle cannot be empty")
    }
    return try identity.withHandle { identityHandle in
      var initiatorHandle: OpaquePointer?
      var handshakeInitBuffer = EppBuffer(data: nil, length: 0)
      var outError = EcliptixProtocolC.EppError(code: EPP_SUCCESS, message: nil)
      var sessionConfig = EcliptixProtocolC.EppSessionConfig(
        max_messages_per_chain: config.maxMessagesPerChain
      )
      let resultCode = peerPrekeyBundle.withUnsafeBytes { peerBytes in
        epp_handshake_initiator_start(
          OpaquePointer(identityHandle),
          peerBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
          peerPrekeyBundle.count,
          &sessionConfig,
          &initiatorHandle,
          &handshakeInitBuffer,
          &outError
        )
      }
      defer {
        if handshakeInitBuffer.data != nil {
          epp_buffer_release(&handshakeInitBuffer)
        }
        epp_error_free(&outError)
      }
      guard resultCode == EPP_SUCCESS else {
        let msg = outError.message.map { String(cString: $0) } ?? "unknown"
        throw ProtocolError.handshakeFailed("Failed to start handshake, code=\(resultCode): \(msg)")
      }
      guard let handle = initiatorHandle else {
        throw ProtocolError.nullPointer("Handshake initiator handle is null")
      }
      guard let bufferData = handshakeInitBuffer.data,
        handshakeInitBuffer.length > 0
      else {
        var mutableHandle: OpaquePointer? = handle
        epp_handshake_initiator_destroy(&mutableHandle)
        throw ProtocolError.bufferTooSmall("Handshake init buffer is empty")
      }

      let handshakeInitData = Data(bytes: bufferData, count: handshakeInitBuffer.length)
      let initiator = HandshakeInitiator(handle: UnsafeMutableRawPointer(handle))
      return (handshakeInitData, initiator)
    }
  }

  func finish(_ handshakeAck: Data) throws -> NativeProtocolSession {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw ProtocolError.objectDisposed("Handshake initiator already disposed")
    }
    guard !handshakeAck.isEmpty else {
      throw ProtocolError.invalidInput("Handshake acknowledgment cannot be empty")
    }

    var sessionHandle: OpaquePointer?
    var outError = EcliptixProtocolC.EppError(code: EPP_SUCCESS, message: nil)
    let resultCode = handshakeAck.withUnsafeBytes { ackBytes in
      epp_handshake_initiator_finish(
        OpaquePointer(handle),
        ackBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
        handshakeAck.count,
        &sessionHandle,
        &outError
      )
    }
    defer { epp_error_free(&outError) }

    guard resultCode == EPP_SUCCESS else {
      let msg = outError.message.map { String(cString: $0) } ?? "unknown"
      throw ProtocolError.handshakeFailed("Failed to finish handshake, code=\(resultCode): \(msg)")
    }
    guard let session = sessionHandle else {
      throw ProtocolError.nullPointer("Session handle is null")
    }
    disposed = true
    return NativeProtocolSession(handle: UnsafeMutableRawPointer(session))
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    var mutableHandle: OpaquePointer? = OpaquePointer(handle)
    epp_handshake_initiator_destroy(&mutableHandle)
  }

  deinit {
    dispose()
  }
}

struct NativeHandshakeInitiatorStart {

  let handshakeInit: Data
  let initiator: HandshakeInitiator
}

struct NativeHandshakeInitiator {

  static func start(
    identity: EcliptixIdentityKeys,
    serverPreKeyBundle: Data,
    chainLimit: UInt32
  ) -> Result<NativeHandshakeInitiatorStart, ProtocolFailure> {
    do {
      let config: EPPNative.EppSessionConfig = EPPNative.EppSessionConfig(
        maxMessagesPerChain: chainLimit
      )
      let (handshakeInit, initiator): (Data, HandshakeInitiator) = try HandshakeInitiator.start(
        identity: identity,
        peerPrekeyBundle: serverPreKeyBundle,
        config: config
      )
      let result: NativeHandshakeInitiatorStart = NativeHandshakeInitiatorStart(
        handshakeInit: handshakeInit,
        initiator: initiator
      )
      return .ok(result)
    } catch let error as ProtocolError {
      return .err(error.toProtocolFailure())
    } catch {
      return .err(.generic(error.localizedDescription))
    }
  }

  static func finish(
    initiator: HandshakeInitiator,
    handshakeResponse: Data
  ) -> Result<NativeProtocolSession, ProtocolFailure> {
    do {
      let session = try initiator.finish(handshakeResponse)
      return .ok(session)
    } catch let error as ProtocolError {
      return .err(error.toProtocolFailure())
    } catch {
      return .err(.generic(error.localizedDescription))
    }
  }
}
