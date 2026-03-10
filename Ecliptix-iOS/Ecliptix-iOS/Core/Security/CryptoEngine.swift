// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

enum CryptoEngineError: Error, Sendable, LocalizedError {
  case ffiError(code: Int32, operation: String)
  case invalidKeyLength(expected: Int, actual: Int)
  case nullHandle(operation: String)
  case serializationFailed(String)
  case deserializationFailed(String)

  var errorDescription: String? {
    switch self {
    case .ffiError(let code, let op):
      return "\(op) failed with FFI code \(code)"
    case .invalidKeyLength(let expected, let actual):
      return "Invalid key length: expected \(expected), got \(actual)"
    case .nullHandle(let op):
      return "\(op) returned null handle"
    case .serializationFailed(let msg):
      return "Serialization failed: \(msg)"
    case .deserializationFailed(let msg):
      return "Deserialization failed: \(msg)"
    }
  }
}

struct GroupEncryptResult: Sendable {
  let ciphertext: Data
}

struct GroupDecryptResult: Sendable {
  let plaintext: Data
  let senderLeafIndex: UInt32
  let generation: UInt32
}

struct GroupAddMemberResult: Sendable {
  let commitBytes: Data
  let welcomeBytes: Data
}

struct GroupSessionInfo: Sendable {
  let groupId: Data
  let epoch: UInt64
  let myLeafIndex: UInt32
  let memberCount: UInt32
}

struct GroupDecryptExResult: Sendable {
  let plaintext: Data
  let senderLeafIndex: UInt32
  let generation: UInt32
  let contentType: UInt32
  let ttlSeconds: UInt32
  let sentTimestamp: UInt64
  let messageId: Data
  let referencedMessageId: Data
  let hasSealedPayload: Bool
  let hasFrankingData: Bool
}

struct SessionPeerIdentity: Sendable {
  let ed25519Public: Data
  let x25519Public: Data
}

struct GroupSecurityPolicy: Sendable {
  let maxMessagesPerEpoch: UInt32
  let maxSkippedKeysPerSender: UInt32
  let blockExternalJoin: Bool
  let enhancedKeySchedule: Bool
  let mandatoryFranking: Bool
}

enum CryptoEngine {

  private static let log = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.ecliptix.app",
    category: "CryptoEngine"
  )

  static let sealKeyLength = 32

  static func initializeRuntime() -> Bool {
    let result = EPPNative.initialize()
    if result != 0 {
      log.error("epp_init() failed with code \(result)")
      return false
    }
    log.info("EPP runtime initialized")
    return true
  }

  static func shutdownRuntime() {
    EPPNative.shutdown()
    log.info("EPP runtime shut down")
  }

  static func createIdentity() throws -> ManagedIdentityHandle {
    var outHandle: EPPNative.EppHandle?
    var outError = EPPNative.EppErrorCode.success
    let result = EPPNative.identityCreate(&outHandle, &outError)
    guard result == 0, let handle = outHandle else {
      throw CryptoEngineError.ffiError(code: result, operation: "identityCreate")
    }
    return ManagedIdentityHandle(handle: handle)
  }

  static func createIdentityFromSeed(_ seed: Data) throws -> ManagedIdentityHandle {
    guard seed.count == EPPConstants.SEED_LENGTH else {
      throw CryptoEngineError.invalidKeyLength(
        expected: EPPConstants.SEED_LENGTH, actual: seed.count)
    }

    var outHandle: EPPNative.EppHandle?
    var outError = EPPNative.EppErrorCode.success
    let result = seed.withUnsafeBytes { seedBytes in
      guard let base = seedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.identityCreateFromSeed(
        base,
        seed.count,
        &outHandle,
        &outError
      )
    }
    guard result == 0, let handle = outHandle else {
      throw CryptoEngineError.ffiError(code: result, operation: "identityCreateFromSeed")
    }
    return ManagedIdentityHandle(handle: handle)
  }

  static func getIdentityEd25519Public(_ identity: ManagedIdentityHandle) throws -> Data {
    try identity.withHandle { handle in
      var keyData = Data(count: EPPConstants.ED25519_PUBLIC_KEY_LENGTH)
      var outError = EPPNative.EppErrorCode.success
      let result = keyData.withUnsafeMutableBytes { keyBytes in
        guard let base = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.identityGetEd25519Public(
          handle,
          base,
          EPPConstants.ED25519_PUBLIC_KEY_LENGTH,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "identityGetEd25519Public")
      }
      return keyData
    }
  }

  static func getIdentityX25519Public(_ identity: ManagedIdentityHandle) throws -> Data {
    try identity.withHandle { handle in
      var keyData = Data(count: EPPConstants.X25519_PUBLIC_KEY_LENGTH)
      var outError = EPPNative.EppErrorCode.success
      let result = keyData.withUnsafeMutableBytes { keyBytes in
        guard let base = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.identityGetX25519Public(
          handle,
          base,
          EPPConstants.X25519_PUBLIC_KEY_LENGTH,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "identityGetX25519Public")
      }
      return keyData
    }
  }

  static func generateKeyPackage(
    identity: ManagedIdentityHandle,
    credential: Data
  ) throws -> (keyPackage: Data, secrets: ManagedKeyPackageSecrets) {
    try identity.withHandle { identityHandle in
      var outKeyPackage = EPPNative.EppBuffer(data: nil, length: 0)
      var outSecrets: EPPNative.EppHandle?
      var outError = EPPNative.EppErrorCode.success
      let result = credential.withUnsafeBytes { credBytes in
        guard let base = credBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupGenerateKeyPackage(
          identityHandle,
          base,
          credential.count,
          &outKeyPackage,
          &outSecrets,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupGenerateKeyPackage")
      }
      defer { EPPNative.bufferRelease(&outKeyPackage) }

      guard let kpPtr = outKeyPackage.data else {
        throw CryptoEngineError.nullHandle(operation: "groupGenerateKeyPackage.keyPackageData")
      }

      let kpData = Data(bytes: kpPtr, count: outKeyPackage.length)
      guard let secretsHandle = outSecrets else {
        throw CryptoEngineError.nullHandle(operation: "groupGenerateKeyPackage.secrets")
      }
      return (kpData, ManagedKeyPackageSecrets(handle: secretsHandle))
    }
  }

  static func groupCreate(
    identity: ManagedIdentityHandle,
    credential: Data
  ) throws -> ManagedGroupSession {
    try identity.withHandle { identityHandle in
      var outHandle: EPPNative.EppHandle?
      var outError = EPPNative.EppErrorCode.success
      let result = credential.withUnsafeBytes { credBytes in
        guard let base = credBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupCreate(
          identityHandle,
          base,
          credential.count,
          &outHandle,
          &outError
        )
      }
      guard result == 0, let handle = outHandle else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupCreate")
      }
      log.info("Group session created")
      return ManagedGroupSession(handle: handle)
    }
  }

  static func groupJoin(
    identity: ManagedIdentityHandle,
    welcomeBytes: Data,
    secrets: ManagedKeyPackageSecrets
  ) throws -> ManagedGroupSession {
    guard let secretsHandle = secrets.consumeHandle() else {
      throw CryptoEngineError.nullHandle(operation: "groupJoin.secrets consumed")
    }
    do {
      return try identity.withHandle { identityHandle in
        var outHandle: EPPNative.EppHandle?
        var outError = EPPNative.EppErrorCode.success
        let result = welcomeBytes.withUnsafeBytes { welcomePtr in
          guard let base = welcomePtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupJoin(
            identityHandle,
            base,
            welcomeBytes.count,
            secretsHandle,
            &outHandle,
            &outError
          )
        }
        guard result == 0, let handle = outHandle else {
          throw CryptoEngineError.ffiError(code: result, operation: "groupJoin")
        }
        log.info("Joined group via Welcome")
        return ManagedGroupSession(handle: handle)
      }
    } catch {
      var mutableSecretsHandle: EPPNative.EppHandle? = secretsHandle
      EPPNative.groupKeyPackageSecretsDestroy(&mutableSecretsHandle)
      throw error
    }
  }

  static func groupJoinExternal(
    identity: ManagedIdentityHandle,
    publicState: Data,
    credential: Data
  ) throws -> (session: ManagedGroupSession, commitBytes: Data) {
    try identity.withHandle { identityHandle in
      var outHandle: EPPNative.EppHandle?
      var outCommit = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = publicState.withUnsafeBytes { psBytes in
        credential.withUnsafeBytes { credBytes in
          guard let psBase = psBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            let credBase = credBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupJoinExternal(
            identityHandle,
            psBase,
            publicState.count,
            credBase,
            credential.count,
            &outHandle,
            &outCommit,
            &outError
          )
        }
      }
      guard result == 0, let handle = outHandle else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupJoinExternal")
      }
      defer { EPPNative.bufferRelease(&outCommit) }

      guard let commitPtr = outCommit.data else {
        throw CryptoEngineError.nullHandle(operation: "groupJoinExternal.commitData")
      }

      let commitData = Data(bytes: commitPtr, count: outCommit.length)
      log.info("Joined group via External Join")
      return (ManagedGroupSession(handle: handle), commitData)
    }
  }

  static func groupAddMember(
    session: ManagedGroupSession,
    keyPackageBytes: Data
  ) throws -> GroupAddMemberResult {
    try session.withHandle { handle in
      var outCommit = EPPNative.EppBuffer(data: nil, length: 0)
      var outWelcome = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = keyPackageBytes.withUnsafeBytes { kpBytes in
        guard let base = kpBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupAddMember(
          handle,
          base,
          keyPackageBytes.count,
          &outCommit,
          &outWelcome,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupAddMember")
      }
      defer {
        EPPNative.bufferRelease(&outCommit)
        EPPNative.bufferRelease(&outWelcome)
      }
      guard let commitPtr = outCommit.data else {
        throw CryptoEngineError.nullHandle(operation: "groupAddMember.commitData")
      }
      guard let welcomePtr = outWelcome.data else {
        throw CryptoEngineError.nullHandle(operation: "groupAddMember.welcomeData")
      }
      return GroupAddMemberResult(
        commitBytes: Data(bytes: commitPtr, count: outCommit.length),
        welcomeBytes: Data(bytes: welcomePtr, count: outWelcome.length)
      )
    }
  }

  static func groupRemoveMember(
    session: ManagedGroupSession,
    leafIndex: UInt32
  ) throws -> Data {
    try session.withHandle { handle in
      var outCommit = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupRemoveMember(handle, leafIndex, &outCommit, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupRemoveMember")
      }
      defer { EPPNative.bufferRelease(&outCommit) }

      guard let commitPtr = outCommit.data else {
        throw CryptoEngineError.nullHandle(operation: "groupRemoveMember.commitData")
      }
      return Data(bytes: commitPtr, count: outCommit.length)
    }
  }

  static func groupUpdate(session: ManagedGroupSession) throws -> Data {
    try session.withHandle { handle in
      var outCommit = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupUpdate(handle, &outCommit, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupUpdate")
      }
      defer { EPPNative.bufferRelease(&outCommit) }

      guard let commitPtr = outCommit.data else {
        throw CryptoEngineError.nullHandle(operation: "groupUpdate.commitData")
      }
      return Data(bytes: commitPtr, count: outCommit.length)
    }
  }

  static func groupProcessCommit(
    session: ManagedGroupSession,
    commitBytes: Data
  ) throws {
    try session.withHandle { handle in
      var outError = EPPNative.EppErrorCode.success
      let result = commitBytes.withUnsafeBytes { commitPtr in
        guard let base = commitPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupProcessCommit(
          handle,
          base,
          commitBytes.count,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupProcessCommit")
      }
    }
  }

  static func groupEncrypt(
    session: ManagedGroupSession,
    plaintext: Data
  ) throws -> GroupEncryptResult {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = plaintext.withUnsafeBytes { ptBytes in
        guard let base = ptBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupEncrypt(
          handle,
          base,
          plaintext.count,
          &outCiphertext,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncrypt")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ctPtr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncrypt.ciphertext")
      }
      return GroupEncryptResult(
        ciphertext: Data(bytes: ctPtr, count: outCiphertext.length)
      )
    }
  }

  static func groupDecrypt(
    session: ManagedGroupSession,
    ciphertext: Data
  ) throws -> GroupDecryptResult {
    try session.withHandle { handle in
      var outPlaintext = EPPNative.EppBuffer(data: nil, length: 0)
      var outSenderLeaf: UInt32 = 0
      var outGeneration: UInt32 = 0
      var outError = EPPNative.EppErrorCode.success
      let result = ciphertext.withUnsafeBytes { ctBytes in
        guard let base = ctBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupDecrypt(
          handle,
          base,
          ciphertext.count,
          &outPlaintext,
          &outSenderLeaf,
          &outGeneration,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupDecrypt")
      }
      defer { EPPNative.bufferRelease(&outPlaintext) }

      guard let ptPtr = outPlaintext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupDecrypt.plaintext")
      }
      return GroupDecryptResult(
        plaintext: Data(bytes: ptPtr, count: outPlaintext.length),
        senderLeafIndex: outSenderLeaf,
        generation: outGeneration
      )
    }
  }

  static func groupEncryptSealed(
    session: ManagedGroupSession,
    plaintext: Data,
    hint: Data
  ) throws -> Data {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = plaintext.withUnsafeBytes { ptBytes in
        hint.withUnsafeBytes { hintBytes in
          guard let ptBase = ptBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
            let hintBase = hintBytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupEncryptSealed(
            handle,
            ptBase,
            plaintext.count,
            hintBase,
            hint.count,
            &outCiphertext,
            &outError
          )
        }
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncryptSealed")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ctPtr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncryptSealed.ciphertext")
      }
      return Data(bytes: ctPtr, count: outCiphertext.length)
    }
  }

  static func groupEncryptDisappearing(
    session: ManagedGroupSession,
    plaintext: Data,
    ttlSeconds: UInt32
  ) throws -> Data {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = plaintext.withUnsafeBytes { ptBytes in
        guard let base = ptBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupEncryptDisappearing(
          handle,
          base,
          plaintext.count,
          ttlSeconds,
          &outCiphertext,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncryptDisappearing")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ctPtr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncryptDisappearing.ciphertext")
      }
      return Data(bytes: ctPtr, count: outCiphertext.length)
    }
  }

  static func groupEncryptFrankable(
    session: ManagedGroupSession,
    plaintext: Data
  ) throws -> Data {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = plaintext.withUnsafeBytes { ptBytes in
        guard let base = ptBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupEncryptFrankable(
          handle,
          base,
          plaintext.count,
          &outCiphertext,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncryptFrankable")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ctPtr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncryptFrankable.ciphertext")
      }
      return Data(bytes: ctPtr, count: outCiphertext.length)
    }
  }

  static func groupInfo(session: ManagedGroupSession) throws -> GroupSessionInfo {
    try session.withHandle { handle in
      var outGroupId = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let idResult = EPPNative.groupGetId(handle, &outGroupId, &outError)
      guard idResult == 0 else {
        throw CryptoEngineError.ffiError(code: idResult, operation: "groupGetId")
      }
      defer { EPPNative.bufferRelease(&outGroupId) }

      guard let groupIdPtr = outGroupId.data else {
        throw CryptoEngineError.nullHandle(operation: "groupGetId.groupId")
      }
      return GroupSessionInfo(
        groupId: Data(bytes: groupIdPtr, count: outGroupId.length),
        epoch: EPPNative.groupGetEpoch(handle),
        myLeafIndex: EPPNative.groupGetMyLeafIndex(handle),
        memberCount: EPPNative.groupGetMemberCount(handle)
      )
    }
  }

  static func groupMemberLeafIndices(session: ManagedGroupSession) throws -> [UInt32] {
    try session.withHandle { handle in
      var outIndices = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupGetMemberLeafIndices(handle, &outIndices, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupGetMemberLeafIndices")
      }
      defer { EPPNative.bufferRelease(&outIndices) }

      let byteCount = outIndices.length
      guard byteCount % 4 == 0 else {
        throw CryptoEngineError.serializationFailed(
          "Leaf indices buffer length \(byteCount) not aligned to 4")
      }

      let count = byteCount / 4
      if count == 0 {
        return []
      }
      guard let indicesPtr = outIndices.data else {
        throw CryptoEngineError.nullHandle(operation: "groupGetMemberLeafIndices.data")
      }

      let rawBytes = UnsafeBufferPointer(start: indicesPtr, count: byteCount)
      var parsedIndices: [UInt32] = []
      parsedIndices.reserveCapacity(count)
      for offset in stride(from: 0, to: byteCount, by: 4) {
        let valueLE =
          UInt32(rawBytes[offset]) | (UInt32(rawBytes[offset + 1]) << 8)
          | (UInt32(rawBytes[offset + 2]) << 16) | (UInt32(rawBytes[offset + 3]) << 24)
        parsedIndices.append(valueLE)
      }
      return parsedIndices
    }
  }

  static func groupExportPublicState(session: ManagedGroupSession) throws -> Data {
    try session.withHandle { handle in
      var outState = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupExportPublicState(handle, &outState, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupExportPublicState")
      }
      defer { EPPNative.bufferRelease(&outState) }

      guard let statePtr = outState.data else {
        throw CryptoEngineError.nullHandle(operation: "groupExportPublicState.data")
      }
      return Data(bytes: statePtr, count: outState.length)
    }
  }

  static func groupSerialize(
    session: ManagedGroupSession,
    sealKey: Data,
    externalCounter: UInt64
  ) throws -> Data {
    guard sealKey.count == sealKeyLength else {
      throw CryptoEngineError.invalidKeyLength(expected: sealKeyLength, actual: sealKey.count)
    }
    return try session.withHandle { handle in
      var outState = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = sealKey.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) -> Int32 in
        guard let base = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupSerialize(
          handle,
          base,
          sealKey.count,
          externalCounter,
          &outState,
          &outError
        )
      }
      guard result == 0 else {
        throw CryptoEngineError.serializationFailed("groupSerialize FFI code \(result)")
      }
      defer { EPPNative.bufferRelease(&outState) }

      guard let statePtr = outState.data else {
        throw CryptoEngineError.serializationFailed("groupSerialize returned null buffer")
      }
      return Data(bytes: statePtr, count: outState.length)
    }
  }

  static func groupDeserialize(
    sealedState: Data,
    sealKey: Data,
    identity: ManagedIdentityHandle,
    minExternalCounter: UInt64
  ) throws -> (session: ManagedGroupSession, externalCounter: UInt64) {
    guard sealKey.count == sealKeyLength else {
      throw CryptoEngineError.invalidKeyLength(expected: sealKeyLength, actual: sealKey.count)
    }
    return try identity.withHandle { identityHandle in
      var outHandle: EPPNative.EppHandle?
      var outExternalCounter: UInt64 = 0
      var outError = EPPNative.EppErrorCode.success
      let stateArr = [UInt8](sealedState)
      let keyArr = [UInt8](sealKey)
      let result = stateArr.withUnsafeBufferPointer { stateBuf in
        keyArr.withUnsafeBufferPointer { keyBuf in
          guard let stateBase = stateBuf.baseAddress,
            let keyBase = keyBuf.baseAddress
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupDeserialize(
            stateBase,
            sealedState.count,
            keyBase,
            sealKey.count,
            minExternalCounter,
            &outExternalCounter,
            identityHandle,
            &outHandle,
            &outError
          )
        }
      }
      guard result == 0, let handle = outHandle else {
        throw CryptoEngineError.deserializationFailed("groupDeserialize FFI code \(result)")
      }
      return (ManagedGroupSession(handle: handle), outExternalCounter)
    }
  }

  static func groupGetPendingReinit(session: ManagedGroupSession) throws -> (
    newGroupId: Data, newVersion: UInt32
  )? {
    try session.withHandle { handle in
      var outNewGroupId = EPPNative.EppBuffer(data: nil, length: 0)
      var outNewVersion: UInt32 = 0
      var outError = EPPNative.EppErrorCode.success
      defer { EPPNative.bufferRelease(&outNewGroupId) }

      let result = EPPNative.groupGetPendingReinit(
        handle, &outNewGroupId, &outNewVersion, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupGetPendingReinit")
      }
      if outNewGroupId.length == 0 {
        return nil
      }
      guard let newGroupIdPtr = outNewGroupId.data else {
        throw CryptoEngineError.nullHandle(operation: "groupGetPendingReinit.newGroupId")
      }
      return (Data(bytes: newGroupIdPtr, count: outNewGroupId.length), outNewVersion)
    }
  }

  static func sessionSerializeSealed(
    sessionHandle: EPPNative.EppHandle,
    sealKey: Data,
    externalCounter: UInt64
  ) throws -> Data {
    guard sealKey.count == sealKeyLength else {
      throw CryptoEngineError.invalidKeyLength(expected: sealKeyLength, actual: sealKey.count)
    }

    var outState = EPPNative.EppBuffer(data: nil, length: 0)
    var outError = EPPNative.EppErrorCode.success
    let result = sealKey.withUnsafeBytes { (keyBytes: UnsafeRawBufferPointer) -> Int32 in
      guard let keyPtr = keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.sessionSerializeSealed(
        sessionHandle,
        keyPtr,
        sealKey.count,
        externalCounter,
        &outState,
        &outError
      )
    }
    guard result == 0 else {
      throw CryptoEngineError.serializationFailed("sessionSerializeSealed FFI code \(result)")
    }
    defer { EPPNative.bufferRelease(&outState) }

    guard let statePtr = outState.data else {
      throw CryptoEngineError.serializationFailed("sessionSerializeSealed returned null buffer")
    }
    return Data(bytes: statePtr, count: outState.length)
  }

  static func sessionDeserializeSealed(
    sealedState: Data,
    sealKey: Data,
    minExternalCounter: UInt64
  ) throws -> (session: ManagedGroupSession, externalCounter: UInt64) {
    guard sealKey.count == sealKeyLength else {
      throw CryptoEngineError.invalidKeyLength(expected: sealKeyLength, actual: sealKey.count)
    }

    var outHandle: EPPNative.EppHandle?
    var outExternalCounter: UInt64 = 0
    var outError = EPPNative.EppErrorCode.success
    let stateArr = [UInt8](sealedState)
    let keyArr = [UInt8](sealKey)
    let result = stateArr.withUnsafeBufferPointer { stateBuf in
      keyArr.withUnsafeBufferPointer { keyBuf in
        guard let stateBase = stateBuf.baseAddress,
          let keyPtr = keyBuf.baseAddress
        else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.sessionDeserializeSealed(
          stateBase,
          sealedState.count,
          keyPtr,
          sealKey.count,
          minExternalCounter,
          &outExternalCounter,
          &outHandle,
          &outError
        )
      }
    }
    guard result == 0, let handle = outHandle else {
      throw CryptoEngineError.deserializationFailed("sessionDeserializeSealed FFI code \(result)")
    }
    return (ManagedGroupSession(handle: handle), outExternalCounter)
  }

  static func groupCreateShielded(
    identity: ManagedIdentityHandle,
    credential: Data
  ) throws -> ManagedGroupSession {
    try identity.withHandle { identityHandle in
      var outHandle: EPPNative.EppHandle?
      var outError = EPPNative.EppErrorCode.success
      let result = credential.withUnsafeBytes { credBytes in
        guard let base = credBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupCreateShielded(
          identityHandle, base, credential.count, &outHandle, &outError)
      }
      guard result == 0, let handle = outHandle else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupCreateShielded")
      }
      return ManagedGroupSession(handle: handle)
    }
  }

  static func groupCreateWithPolicy(
    identity: ManagedIdentityHandle,
    credential: Data,
    policy: GroupSecurityPolicy
  ) throws -> ManagedGroupSession {
    try identity.withHandle { identityHandle in
      var outHandle: EPPNative.EppHandle?
      var outError = EPPNative.EppErrorCode.success
      var cPolicy = EPPNative.EppGroupSecurityPolicy(
        maxMessagesPerEpoch: policy.maxMessagesPerEpoch,
        maxSkippedKeysPerSender: policy.maxSkippedKeysPerSender,
        blockExternalJoin: policy.blockExternalJoin ? 1 : 0,
        enhancedKeySchedule: policy.enhancedKeySchedule ? 1 : 0,
        mandatoryFranking: policy.mandatoryFranking ? 1 : 0
      )
      let result = credential.withUnsafeBytes { credBytes in
        guard let base = credBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupCreateWithPolicy(
          identityHandle, base, credential.count, &cPolicy, &outHandle, &outError)
      }
      guard result == 0, let handle = outHandle else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupCreateWithPolicy")
      }
      return ManagedGroupSession(handle: handle)
    }
  }

  static func groupGetSecurityPolicy(session: ManagedGroupSession) throws -> GroupSecurityPolicy {
    try session.withHandle { handle in
      var outPolicy = EPPNative.EppGroupSecurityPolicy()
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupGetSecurityPolicy(handle, &outPolicy, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupGetSecurityPolicy")
      }
      return GroupSecurityPolicy(
        maxMessagesPerEpoch: outPolicy.maxMessagesPerEpoch,
        maxSkippedKeysPerSender: outPolicy.maxSkippedKeysPerSender,
        blockExternalJoin: outPolicy.blockExternalJoin != 0,
        enhancedKeySchedule: outPolicy.enhancedKeySchedule != 0,
        mandatoryFranking: outPolicy.mandatoryFranking != 0
      )
    }
  }

  static func groupIsShielded(session: ManagedGroupSession) throws -> Bool {
    try session.withHandle { handle in
      var outShielded: UInt8 = 0
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.groupIsShielded(handle, &outShielded, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupIsShielded")
      }
      return outShielded != 0
    }
  }

  static func groupDecryptEx(
    session: ManagedGroupSession,
    ciphertext: Data
  ) throws -> GroupDecryptExResult {
    try session.withHandle { handle in
      var outResult = EPPNative.EppGroupDecryptResult()
      var outError = EPPNative.EppErrorCode.success
      let code = ciphertext.withUnsafeBytes { ctBytes in
        guard let base = ctBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupDecryptEx(handle, base, ciphertext.count, &outResult, &outError)
      }
      guard code == 0 else {
        throw CryptoEngineError.ffiError(code: code, operation: "groupDecryptEx")
      }
      defer { EPPNative.groupDecryptResultFree(&outResult) }

      let plaintext =
        outResult.plaintext.data.map { Data(bytes: $0, count: outResult.plaintext.length) }
        ?? Data()
      let msgId =
        outResult.messageId.data.map { Data(bytes: $0, count: outResult.messageId.length) }
        ?? Data()
      let refMsgId =
        outResult.referencedMessageId.data.map {
          Data(bytes: $0, count: outResult.referencedMessageId.length)
        } ?? Data()
      return GroupDecryptExResult(
        plaintext: plaintext,
        senderLeafIndex: outResult.senderLeafIndex,
        generation: outResult.generation,
        contentType: outResult.contentType,
        ttlSeconds: outResult.ttlSeconds,
        sentTimestamp: outResult.sentTimestamp,
        messageId: msgId,
        referencedMessageId: refMsgId,
        hasSealedPayload: outResult.hasSealedPayload != 0,
        hasFrankingData: outResult.hasFrankingData != 0
      )
    }
  }

  static func groupEncryptEdit(
    session: ManagedGroupSession,
    newContent: Data,
    targetMessageId: Data
  ) throws -> Data {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let contentArr = [UInt8](newContent)
      let idArr = [UInt8](targetMessageId)
      let result = contentArr.withUnsafeBufferPointer { contentBuf in
        idArr.withUnsafeBufferPointer { idBuf in
          guard let contentBase = contentBuf.baseAddress,
            let idBase = idBuf.baseAddress
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupEncryptEdit(
            handle,
            contentBase, newContent.count,
            idBase, targetMessageId.count,
            &outCiphertext, &outError
          )
        }
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncryptEdit")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ptr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncryptEdit.ciphertext")
      }
      return Data(bytes: ptr, count: outCiphertext.length)
    }
  }

  static func groupEncryptDelete(
    session: ManagedGroupSession,
    targetMessageId: Data
  ) throws -> Data {
    try session.withHandle { handle in
      var outCiphertext = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = targetMessageId.withUnsafeBytes { idBytes in
        guard let idBase = idBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
          return EPPNative.EppErrorCode.errorInvalidInput.rawValue
        }
        return EPPNative.groupEncryptDelete(
          handle, idBase, targetMessageId.count, &outCiphertext, &outError)
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupEncryptDelete")
      }
      defer { EPPNative.bufferRelease(&outCiphertext) }

      guard let ptr = outCiphertext.data else {
        throw CryptoEngineError.nullHandle(operation: "groupEncryptDelete.ciphertext")
      }
      return Data(bytes: ptr, count: outCiphertext.length)
    }
  }

  static func groupComputeMessageId(
    groupId: Data,
    epoch: UInt64,
    senderLeafIndex: UInt32,
    generation: UInt32
  ) throws -> Data {
    var outMessageId = EPPNative.EppBuffer(data: nil, length: 0)
    var outError = EPPNative.EppErrorCode.success
    let result = groupId.withUnsafeBytes { idBytes in
      guard let idBase = idBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
        return EPPNative.EppErrorCode.errorInvalidInput.rawValue
      }
      return EPPNative.groupComputeMessageId(
        idBase, groupId.count,
        epoch, senderLeafIndex, generation,
        &outMessageId, &outError
      )
    }
    guard result == 0 else {
      throw CryptoEngineError.ffiError(code: result, operation: "groupComputeMessageId")
    }
    defer { EPPNative.bufferRelease(&outMessageId) }

    guard let ptr = outMessageId.data else {
      throw CryptoEngineError.nullHandle(operation: "groupComputeMessageId.messageId")
    }
    return Data(bytes: ptr, count: outMessageId.length)
  }

  static func groupSetPsk(
    session: ManagedGroupSession,
    pskId: Data,
    psk: Data
  ) throws {
    try session.withHandle { handle in
      var outError = EPPNative.EppErrorCode.success
      let idArr = [UInt8](pskId)
      let pskArr = [UInt8](psk)
      let result = idArr.withUnsafeBufferPointer { idBuf in
        pskArr.withUnsafeBufferPointer { pskBuf in
          guard let idBase = idBuf.baseAddress,
            let pskBase = pskBuf.baseAddress
          else {
            return EPPNative.EppErrorCode.errorInvalidInput.rawValue
          }
          return EPPNative.groupSetPsk(handle, idBase, pskId.count, pskBase, psk.count, &outError)
        }
      }
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "groupSetPsk")
      }
    }
  }

  static func sessionNonceRemaining(sessionHandle: EPPNative.EppHandle) throws -> UInt64 {
    var outRemaining: UInt64 = 0
    var outError = EPPNative.EppErrorCode.success
    let result = EPPNative.sessionNonceRemaining(sessionHandle, &outRemaining, &outError)
    guard result == 0 else {
      throw CryptoEngineError.ffiError(code: result, operation: "sessionNonceRemaining")
    }
    return outRemaining
  }

  static func sessionGetId(sessionHandle: EPPNative.EppHandle) throws -> Data {
    var outSessionId = EPPNative.EppBuffer(data: nil, length: 0)
    var outError = EPPNative.EppErrorCode.success
    let result = EPPNative.sessionGetId(sessionHandle, &outSessionId, &outError)
    guard result == 0 else {
      throw CryptoEngineError.ffiError(code: result, operation: "sessionGetId")
    }
    defer { EPPNative.bufferRelease(&outSessionId) }

    guard let ptr = outSessionId.data else {
      throw CryptoEngineError.nullHandle(operation: "sessionGetId.sessionId")
    }
    return Data(bytes: ptr, count: outSessionId.length)
  }

  static func sessionGetPeerIdentity(sessionHandle: EPPNative.EppHandle) throws
    -> SessionPeerIdentity
  {
    var outIdentity = EPPNative.EppSessionPeerIdentity()
    var outError = EPPNative.EppErrorCode.success
    let result = EPPNative.sessionGetPeerIdentity(sessionHandle, &outIdentity, &outError)
    guard result == 0 else {
      throw CryptoEngineError.ffiError(code: result, operation: "sessionGetPeerIdentity")
    }
    return SessionPeerIdentity(
      ed25519Public: tupleToData(outIdentity.ed25519Public),
      x25519Public: tupleToData(outIdentity.x25519Public)
    )
  }

  static func sessionGetLocalIdentity(sessionHandle: EPPNative.EppHandle) throws
    -> SessionPeerIdentity
  {
    var outIdentity = EPPNative.EppSessionPeerIdentity()
    var outError = EPPNative.EppErrorCode.success
    let result = EPPNative.sessionGetLocalIdentity(sessionHandle, &outIdentity, &outError)
    guard result == 0 else {
      throw CryptoEngineError.ffiError(code: result, operation: "sessionGetLocalIdentity")
    }
    return SessionPeerIdentity(
      ed25519Public: tupleToData(outIdentity.ed25519Public),
      x25519Public: tupleToData(outIdentity.x25519Public)
    )
  }

  static func prekeyBundleReplenish(
    identity: ManagedIdentityHandle,
    count: UInt32
  ) throws -> Data {
    try identity.withHandle { identityHandle in
      var outKeys = EPPNative.EppBuffer(data: nil, length: 0)
      var outError = EPPNative.EppErrorCode.success
      let result = EPPNative.prekeyBundleReplenish(identityHandle, count, &outKeys, &outError)
      guard result == 0 else {
        throw CryptoEngineError.ffiError(code: result, operation: "prekeyBundleReplenish")
      }
      defer { EPPNative.bufferRelease(&outKeys) }

      guard let ptr = outKeys.data else {
        throw CryptoEngineError.nullHandle(operation: "prekeyBundleReplenish.keys")
      }
      return Data(bytes: ptr, count: outKeys.length)
    }
  }
}

private func tupleToData(
  _ tuple: (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
  )
) -> Data {
  var t = tuple
  return withUnsafeBytes(of: &t) { Data($0) }
}
