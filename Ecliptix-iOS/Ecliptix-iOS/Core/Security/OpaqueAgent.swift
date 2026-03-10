// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class OpaqueAgent: @unchecked Sendable {

  private let clientHandle: OpaqueNative.OpaqueClientHandle
  private var disposed: Bool = false
  private let lock: NSLock = NSLock()

  init(serverPublicKey: Data) throws {
    try OpaqueNative.initialize()
    guard serverPublicKey.count == OpaqueNative.PUBLIC_KEY_LENGTH else {
      throw OpaqueError.invalidPublicKey(
        "Server public key must be \(OpaqueNative.PUBLIC_KEY_LENGTH) bytes, got \(serverPublicKey.count)"
      )
    }

    var handle: OpaqueNative.OpaqueClientHandle?
    let resultCode: Int32 = serverPublicKey.withUnsafeBytes {
      (publicKeyBytes: UnsafeRawBufferPointer) in
      guard let typedPointer = publicKeyBytes.bindMemory(to: UInt8.self).baseAddress else {
        return OpaqueNative.ResultCode.invalidInput.rawValue
      }
      return OpaqueNative.clientCreate(typedPointer, &handle)
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "Client initialization")
    }
    guard let clientHandle: OpaqueNative.OpaqueClientHandle = handle else {
      throw OpaqueError.memoryError("Failed to create OPAQUE client handle")
    }
    self.clientHandle = clientHandle
  }

  func createRegistrationRequest(_ password: Data) throws -> RegistrationResult {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("OpaqueAgent accessed after disposal")
    }
    guard !password.isEmpty else {
      throw OpaqueError.invalidInput("Password cannot be empty")
    }

    var stateHandle: OpaqueNative.RegistrationStateHandle?
    var requestBytes: [UInt8] = [UInt8](
      repeating: 0, count: OpaqueNative.REGISTRATION_REQUEST_LENGTH)
    let resultCode: Int32 = password.withUnsafeBytes { (passwordBytes: UnsafeRawBufferPointer) in
      guard let passwordPointer = passwordBytes.bindMemory(to: UInt8.self).baseAddress else {
        return OpaqueNative.ResultCode.invalidInput.rawValue
      }
      return requestBytes.withUnsafeMutableBytes { (requestBuffer: UnsafeMutableRawBufferPointer) in
        guard let requestPointer = requestBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return OpaqueNative.ResultCode.invalidInput.rawValue
        }
        return OpaqueNative.registrationRequestCreate(
          clientHandle,
          passwordPointer,
          password.count,
          &stateHandle,
          requestPointer
        )
      }
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "Registration request creation")
    }
    guard let handle: OpaqueNative.RegistrationStateHandle = stateHandle else {
      throw OpaqueError.memoryError("Failed to create registration state handle")
    }

    let requestData: Data = Data(requestBytes)
    let registrationResult: RegistrationResult = RegistrationResult(
      stateHandle: handle, requestData: requestData)
    return registrationResult
  }

  func finalizeRegistration(_ response: Data, _ registrationState: RegistrationResult) throws
    -> Data
  {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("OpaqueAgent accessed after disposal")
    }
    guard response.count == OpaqueNative.REGISTRATION_RESPONSE_LENGTH else {
      throw OpaqueError.invalidInput(
        "Registration response must be \(OpaqueNative.REGISTRATION_RESPONSE_LENGTH) bytes, got \(response.count)"
      )
    }

    var recordBytes: [UInt8] = [UInt8](repeating: 0, count: OpaqueNative.REGISTRATION_RECORD_LENGTH)
    let resultCode: Int32 = try registrationState.withHandle { stateHandle in
      response.withUnsafeBytes { (responseBytes: UnsafeRawBufferPointer) in
        guard let responsePointer = responseBytes.bindMemory(to: UInt8.self).baseAddress else {
          return OpaqueNative.ResultCode.invalidInput.rawValue
        }
        return recordBytes.withUnsafeMutableBytes { (recordBuffer: UnsafeMutableRawBufferPointer) in
          guard let recordPointer = recordBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return OpaqueNative.ResultCode.invalidInput.rawValue
          }
          return OpaqueNative.registrationFinalize(
            clientHandle,
            responsePointer,
            stateHandle,
            recordPointer
          )
        }
      }
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "Registration finalization")
    }
    return Data(recordBytes)
  }

  func generateKe1(_ password: Data) throws -> KeyExchangeResult {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("OpaqueAgent accessed after disposal")
    }
    guard !password.isEmpty else {
      throw OpaqueError.invalidInput("Password cannot be empty")
    }

    var stateHandle: OpaqueNative.KeyExchangeStateHandle?
    var ke1Bytes: [UInt8] = [UInt8](repeating: 0, count: OpaqueNative.KE1_LENGTH)
    let resultCode: Int32 = password.withUnsafeBytes { (passwordBytes: UnsafeRawBufferPointer) in
      guard let passwordPointer = passwordBytes.bindMemory(to: UInt8.self).baseAddress else {
        return OpaqueNative.ResultCode.invalidInput.rawValue
      }
      return ke1Bytes.withUnsafeMutableBytes { (ke1Buffer: UnsafeMutableRawBufferPointer) in
        guard let ke1Pointer = ke1Buffer.bindMemory(to: UInt8.self).baseAddress else {
          return OpaqueNative.ResultCode.invalidInput.rawValue
        }
        return OpaqueNative.ke1Generate(
          clientHandle,
          passwordPointer,
          password.count,
          &stateHandle,
          ke1Pointer
        )
      }
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "KE1 generation")
    }
    guard let handle: OpaqueNative.KeyExchangeStateHandle = stateHandle else {
      throw OpaqueError.memoryError("Failed to create key exchange state handle")
    }

    let ke1Data: Data = Data(ke1Bytes)
    let keyExchangeResult: KeyExchangeResult = KeyExchangeResult(
      stateHandle: handle, ke1Data: ke1Data)
    return keyExchangeResult
  }

  func generateKe3(_ ke2: Data, _ keyExchangeState: KeyExchangeResult) throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("OpaqueAgent accessed after disposal")
    }
    guard ke2.count == OpaqueNative.KE2_LENGTH else {
      throw OpaqueError.invalidInput(
        "KE2 message must be \(OpaqueNative.KE2_LENGTH) bytes, got \(ke2.count)"
      )
    }

    var ke3Bytes: [UInt8] = [UInt8](repeating: 0, count: OpaqueNative.KE3_LENGTH)
    let resultCode: Int32 = try keyExchangeState.withHandle { keStateHandle in
      ke2.withUnsafeBytes { (ke2BytesPointer: UnsafeRawBufferPointer) in
        guard let ke2Pointer = ke2BytesPointer.bindMemory(to: UInt8.self).baseAddress else {
          return OpaqueNative.ResultCode.invalidInput.rawValue
        }
        return ke3Bytes.withUnsafeMutableBytes { (ke3Buffer: UnsafeMutableRawBufferPointer) in
          guard let ke3Pointer = ke3Buffer.bindMemory(to: UInt8.self).baseAddress else {
            return OpaqueNative.ResultCode.invalidInput.rawValue
          }
          return OpaqueNative.ke3Generate(
            clientHandle,
            ke2Pointer,
            keStateHandle,
            ke3Pointer
          )
        }
      }
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "KE3 generation")
    }
    return Data(ke3Bytes)
  }

  func deriveBaseMasterKey(_ keyExchangeState: KeyExchangeResult) throws -> (
    sessionKey: Data, masterKey: Data
  ) {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      throw OpaqueError.memoryError("OpaqueAgent accessed after disposal")
    }

    var sessionKeyBytes: [UInt8] = [UInt8](repeating: 0, count: OpaqueNative.SESSION_KEY_LENGTH)
    var masterKeyBytes: [UInt8] = [UInt8](repeating: 0, count: OpaqueNative.MASTER_KEY_LENGTH)
    defer {
      OpaqueNative.secureZero(&sessionKeyBytes, sessionKeyBytes.count)
      OpaqueNative.secureZero(&masterKeyBytes, masterKeyBytes.count)
    }

    let resultCode: Int32 = try keyExchangeState.withHandle { keStateHandle in
      sessionKeyBytes.withUnsafeMutableBytes { (sessionBuffer: UnsafeMutableRawBufferPointer) in
        guard let sessionPointer = sessionBuffer.bindMemory(to: UInt8.self).baseAddress else {
          return OpaqueNative.ResultCode.invalidInput.rawValue
        }
        return masterKeyBytes.withUnsafeMutableBytes {
          (masterBuffer: UnsafeMutableRawBufferPointer) in
          guard let masterPointer = masterBuffer.bindMemory(to: UInt8.self).baseAddress else {
            return OpaqueNative.ResultCode.invalidInput.rawValue
          }
          return OpaqueNative.deriveMasterKey(
            clientHandle,
            keStateHandle,
            sessionPointer,
            masterPointer
          )
        }
      }
    }
    guard resultCode == OpaqueNative.ResultCode.success.rawValue else {
      throw OpaqueError.from(resultCode: resultCode, context: "Master key derivation")
    }

    let sessionKey: Data = Data(sessionKeyBytes)
    let masterKey: Data = Data(masterKeyBytes)
    return (sessionKey, masterKey)
  }

  func dispose() {
    lock.lock()
    defer { lock.unlock() }

    guard !disposed else {
      return
    }
    disposed = true
    OpaqueNative.clientDestroy(clientHandle)
  }

  deinit {
    dispose()
  }
}
