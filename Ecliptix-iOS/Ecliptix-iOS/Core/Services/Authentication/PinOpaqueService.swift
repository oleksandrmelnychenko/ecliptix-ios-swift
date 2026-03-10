// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os

final class PinOpaqueService: @unchecked Sendable {

  private let secureSessionClient: any SecureSessionClient
  private let pinRpcService: PinRpcService
  private let secureStorageService: SecureStorageService
  private let agentCache = OpaqueAgentCache()

  init(
    secureSessionClient: any SecureSessionClient,
    pinRpcService: PinRpcService,
    secureStorageService: SecureStorageService
  ) {
    self.secureSessionClient = secureSessionClient
    self.pinRpcService = pinRpcService
    self.secureStorageService = secureStorageService
  }

  func registerPin(
    pinCode: SecureTextBuffer,
    pinLength: Int32,
    connectId: UInt32
  ) async -> Result<Unit, PinOpaqueFailure> {
    AppLogger.auth.info(
      "PinOpaqueRegister: start connectId=\(connectId, privacy: .public), pinLength=\(pinLength, privacy: .public)"
    )
    guard pinLength >= AppConstants.PinOpaque.minPinLength,
      pinLength <= AppConstants.PinOpaque.maxPinLength
    else {
      return .err(.invalidPinLength(ErrorI18NKeys.pinInvalidLength))
    }
    guard var pinData = pinCode.withSecureBytes({ Data($0) }), !pinData.isEmpty else {
      AppLogger.auth.warning("PinOpaqueRegister: empty PIN data")
      return .err(.cryptoFailed(ErrorI18NKeys.secureKeyRequired))
    }
    defer { OpaqueNative.secureZeroData(&pinData) }

    let serverPublicKeyResult = await ensureServerPublicKey(connectId: connectId)
    guard let serverPublicKey = serverPublicKeyResult.ok() else {
      if case .err(let failure) = serverPublicKeyResult {
        return .err(failure)
      }
      return .err(.unexpectedError("Server public key unavailable"))
    }
    do {
      let opaqueAgent = try agentCache.getOrCreateAgent(serverPublicKey: serverPublicKey)
      let registrationState = try opaqueAgent.createRegistrationRequest(pinData)
      defer { registrationState.dispose() }

      guard var requestData = registrationState.getRequestCopy() else {
        AppLogger.auth.error("PinOpaqueRegister: registration request data unavailable")
        return .err(.cryptoFailed(ErrorI18NKeys.pinRegisterFailed))
      }
      defer { OpaqueNative.secureZeroData(&requestData) }

      var initRequest = PinRegisterInitRequest()
      initRequest.peerOprf = requestData
      initRequest.pinLength = pinLength
      initRequest.scope = .account
      let initResult = await pinRpcService.pinRegisterInit(
        request: initRequest,
        connectId: connectId
      )
      guard let initResponse = initResult.ok() else {
        let rpcError = initResult.unwrapErr()
        AppLogger.auth.error(
          "PinOpaqueRegister: init RPC failed, error=\(rpcError.logDescription, privacy: .public)")
        return .err(.networkFailed(rpcError))
      }

      let initValidation = mapPinOpaqueResult(initResponse.result, message: initResponse.message)
      if case .err(let failure) = initValidation {
        AppLogger.auth.warning(
          "PinOpaqueRegister: init server rejected result=\(initResponse.result.rawValue, privacy: .public)"
        )
        return .err(failure)
      }

      var registrationRecord = try opaqueAgent.finalizeRegistration(
        initResponse.peerOprf,
        registrationState
      )
      defer { OpaqueNative.secureZeroData(&registrationRecord) }

      var completeRequest = PinRegisterCompleteRequest()
      completeRequest.peerRegistrationRecord = registrationRecord
      completeRequest.pinLength = pinLength
      completeRequest.scope = .account
      let completeResult = await pinRpcService.pinRegisterComplete(
        request: completeRequest,
        connectId: connectId
      )
      guard let completeResponse = completeResult.ok() else {
        let rpcError = completeResult.unwrapErr()
        AppLogger.auth.error(
          "PinOpaqueRegister: complete RPC failed, error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(.networkFailed(rpcError))
      }

      let completeValidation = mapPinOpaqueResult(
        completeResponse.result, message: completeResponse.message)
      if case .err(let failure) = completeValidation {
        AppLogger.auth.warning(
          "PinOpaqueRegister: complete server rejected result=\(completeResponse.result.rawValue, privacy: .public)"
        )
        return .err(failure)
      }
      AppLogger.auth.info("PinOpaqueRegister: success connectId=\(connectId, privacy: .public)")
      return .ok(Unit.value)
    } catch let error as OpaqueError {
      AppLogger.auth.error("PinOpaqueRegister: OPAQUE error=\(error.message, privacy: .public)")
      return .err(.cryptoFailed(error.message))
    } catch {
      AppLogger.auth.error(
        "PinOpaqueRegister: unexpected error=\(error.localizedDescription, privacy: .public)")
      return .err(.unexpectedError(error.localizedDescription))
    }
  }

  func verifyPin(
    accountId: UUID,
    pinCode: SecureTextBuffer,
    connectId: UInt32
  ) async -> Result<Unit, PinOpaqueFailure> {
    AppLogger.auth.info(
      "PinOpaqueVerify: start connectId=\(connectId, privacy: .public), accountId=\(accountId.uuidString, privacy: .public)"
    )
    let pinLength = pinCode.length
    guard pinLength >= Int(AppConstants.PinOpaque.minPinLength),
      pinLength <= Int(AppConstants.PinOpaque.maxPinLength)
    else {
      return .err(.invalidPinLength(ErrorI18NKeys.pinInvalidLength))
    }
    guard var pinData = pinCode.withSecureBytes({ Data($0) }), !pinData.isEmpty else {
      AppLogger.auth.warning("PinOpaqueVerify: empty PIN data")
      return .err(.cryptoFailed(ErrorI18NKeys.secureKeyRequired))
    }

    let isAllDigits = pinData.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    guard isAllDigits else {
      OpaqueNative.secureZeroData(&pinData)
      return .err(.invalidPinLength(ErrorI18NKeys.pinInvalidLength))
    }
    defer { OpaqueNative.secureZeroData(&pinData) }

    let serverPublicKeyResult = await ensureServerPublicKey(connectId: connectId)
    guard let serverPublicKey = serverPublicKeyResult.ok() else {
      if case .err(let failure) = serverPublicKeyResult {
        return .err(failure)
      }
      return .err(.unexpectedError("Server public key unavailable"))
    }
    do {
      let opaqueAgent = try agentCache.getOrCreateAgent(serverPublicKey: serverPublicKey)
      let ke1 = try opaqueAgent.generateKe1(pinData)
      defer { ke1.dispose() }

      guard var ke1Data = ke1.getKeyExchangeDataCopy() else {
        return .err(.cryptoFailed(ErrorI18NKeys.keyExchangeUnavailable))
      }
      defer { OpaqueNative.secureZeroData(&ke1Data) }

      var initRequest = PinVerifyInitRequest()
      initRequest.accountID = accountId.protobufBytes
      initRequest.peerOprf = ke1Data
      initRequest.scope = .account
      let initResult = await pinRpcService.pinVerifyInit(
        request: initRequest,
        connectId: connectId
      )
      guard let initResponse = initResult.ok() else {
        let rpcError = initResult.unwrapErr()
        AppLogger.auth.error(
          "PinOpaqueVerify: init RPC failed, error=\(rpcError.logDescription, privacy: .public)")
        return .err(.networkFailed(rpcError))
      }
      AppLogger.auth.debug(
        "PinOpaqueVerify: init result=\(initResponse.result.rawValue, privacy: .public)")
      let initValidation = mapPinVerifyResult(
        initResponse.result,
        message: initResponse.message,
        attemptsRemaining: initResponse.attemptsRemaining,
        lockoutSeconds: initResponse.lockoutSeconds
      )
      if case .err(let failure) = initValidation {
        return .err(failure)
      }

      var ke2 = initResponse.serverOprfResponse
      defer { OpaqueNative.secureZeroData(&ke2) }

      var ke3 = try opaqueAgent.generateKe3(ke2, ke1)
      defer { OpaqueNative.secureZeroData(&ke3) }

      var finalizeRequest = PinVerifyFinalizeRequest()
      finalizeRequest.clientMac = ke3
      finalizeRequest.clientEphemeralPublicKey = ke1Data
      finalizeRequest.serverStateToken = initResponse.serverStateToken
      let finalizeResult = await pinRpcService.pinVerifyFinalize(
        request: finalizeRequest,
        connectId: connectId
      )
      guard let finalizeResponse = finalizeResult.ok() else {
        let rpcError = finalizeResult.unwrapErr()
        AppLogger.auth.error(
          "PinOpaqueVerify: finalize RPC failed, error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(.networkFailed(rpcError))
      }
      AppLogger.auth.debug(
        "PinOpaqueVerify: finalize result=\(finalizeResponse.result.rawValue, privacy: .public)")
      let finalizeValidation = mapPinVerifyResult(
        finalizeResponse.result,
        message: finalizeResponse.message,
        attemptsRemaining: finalizeResponse.attemptsRemaining,
        lockoutSeconds: finalizeResponse.lockoutSeconds
      )
      if case .err(let failure) = finalizeValidation {
        return .err(failure)
      }
      AppLogger.auth.info("PinOpaqueVerify: success connectId=\(connectId, privacy: .public)")
      return .ok(Unit.value)
    } catch let error as OpaqueError {
      AppLogger.auth.error("PinOpaqueVerify: OPAQUE error=\(error.message, privacy: .public)")
      switch error {
      case .authenticationError, .invalidInput, .validationError:
        return .err(.invalidPin(remaining: 0, message: ErrorI18NKeys.pinVerifyFailed))
      case .invalidPublicKey, .cryptoError, .memoryError, .unknownError:
        return .err(.cryptoFailed(error.message))
      }
    } catch {
      AppLogger.auth.error(
        "PinOpaqueVerify: unexpected error=\(error.localizedDescription, privacy: .public)")
      return .err(.unexpectedError(error.localizedDescription))
    }
  }

  func changePin(
    newPinCode: SecureTextBuffer,
    newPinLength: Int32,
    connectId: UInt32
  ) async -> Result<Unit, PinOpaqueFailure> {
    AppLogger.auth.info("PinOpaqueChange: start connectId=\(connectId, privacy: .public)")
    return await registerPin(
      pinCode: newPinCode,
      pinLength: newPinLength,
      connectId: connectId
    )
  }

  func disablePin(
    connectId: UInt32
  ) async -> Result<PinDisableResponse, PinOpaqueFailure> {
    AppLogger.auth.info(
      "PinOpaqueDisable: start connectId=\(connectId, privacy: .public)"
    )
    var request = PinDisableRequest()
    request.scope = .account
    let rpcResult = await pinRpcService.pinDisable(
      request: request,
      connectId: connectId
    )
    guard let response = rpcResult.ok() else {
      let rpcError = rpcResult.unwrapErr()
      AppLogger.auth.error(
        "PinOpaqueDisable: RPC failed, error=\(rpcError.logDescription, privacy: .public)")
      return .err(.networkFailed(rpcError))
    }

    let validation = mapPinOpaqueResult(response.result, message: response.message)
    if case .err(let failure) = validation {
      AppLogger.auth.warning(
        "PinOpaqueDisable: server rejected result=\(response.result.rawValue, privacy: .public)")
      return .err(failure)
    }
    AppLogger.auth.info(
      "PinOpaqueDisable: success disabledCount=\(response.disabledCount, privacy: .public)")
    return .ok(response)
  }

  private func ensureServerPublicKey(connectId: UInt32) async -> Result<Data, PinOpaqueFailure> {
    let keyResult = await secureSessionClient.getServerPublicKey(connectId: connectId)
    if let key = keyResult.ok() {
      return .ok(key)
    }
    AppLogger.auth.info(
      "PinOpaque: no server public key for connectId=\(connectId, privacy: .public), establishing session"
    )
    let settings = secureStorageService.settings
    let deviceId = settings?.deviceId ?? NetworkConfiguration.default.deviceId
    let appInstanceId = settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    secureSessionClient.initiateProtocol(
      deviceId: deviceId,
      appInstanceId: appInstanceId,
      connectId: connectId
    )
    let channelResult = await secureSessionClient.establishSecrecyChannel(connectId: connectId)
    guard channelResult.isOk else {
      let errorMessage = channelResult.err() ?? "Failed to establish session"
      AppLogger.auth.error(
        "PinOpaque: session establishment failed connectId=\(connectId, privacy: .public), error=\(errorMessage, privacy: .public)"
      )
      return .err(.networkFailed(.unexpected(errorMessage)))
    }

    let retryResult = await secureSessionClient.getServerPublicKey(connectId: connectId)
    guard let key = retryResult.ok() else {
      let errorMessage = retryResult.err()?.message ?? "Unknown error"
      AppLogger.auth.error(
        "PinOpaque: server public key still unavailable after session establishment connectId=\(connectId, privacy: .public)"
      )
      return .err(.networkFailed(.unexpected(errorMessage)))
    }
    return .ok(key)
  }

  private func mapPinOpaqueResult(
    _ result: PinOpaqueResult,
    message: String
  ) -> Result<Unit, PinOpaqueFailure> {
    switch result {
    case .succeeded:
      return .ok(Unit.value)
    case .invalidPinLength:
      return .err(.invalidPinLength(message.isEmpty ? ErrorI18NKeys.pinInvalidLength : message))
    case .accountNotFound:
      return .err(.accountNotFound(message.isEmpty ? ErrorI18NKeys.pinAccountNotFound : message))
    case .notRegistered:
      return .err(.notRegistered(message.isEmpty ? ErrorI18NKeys.pinNotRegistered : message))
    case .locked:
      return .err(
        .locked(remaining: 0, message: message.isEmpty ? ErrorI18NKeys.pinLocked : message))
    case .attemptsExceeded:
      return .err(
        .attemptsExceeded(
          remaining: 0, message: message.isEmpty ? ErrorI18NKeys.pinLocked : message))
    case .failed:
      return .err(
        .invalidPin(
          remaining: 0, message: message.isEmpty ? ErrorI18NKeys.pinVerifyFailed : message))
    default:
      if !message.isEmpty {
        return .err(.unexpectedError(message))
      }
      return .err(.unexpectedError(ErrorI18NKeys.pinVerifyFailed))
    }
  }

  private func mapPinVerifyResult(
    _ result: PinOpaqueResult,
    message: String,
    attemptsRemaining: UInt32,
    lockoutSeconds: UInt32
  ) -> Result<Unit, PinOpaqueFailure> {
    switch result {
    case .succeeded:
      return .ok(Unit.value)
    case .notRegistered:
      return .err(.notRegistered(message.isEmpty ? ErrorI18NKeys.pinNotRegistered : message))
    case .locked:
      return .err(
        .locked(
          remaining: lockoutSeconds, message: message.isEmpty ? ErrorI18NKeys.pinLocked : message))
    case .attemptsExceeded:
      return .err(
        .attemptsExceeded(
          remaining: attemptsRemaining, message: message.isEmpty ? ErrorI18NKeys.pinLocked : message
        ))
    case .failed:
      return .err(
        .invalidPin(
          remaining: attemptsRemaining,
          message: message.isEmpty ? ErrorI18NKeys.pinVerifyFailed : message))
    case .accountNotFound:
      return .err(.accountNotFound(message.isEmpty ? ErrorI18NKeys.pinAccountNotFound : message))
    default:
      if !message.isEmpty {
        return .err(.unexpectedError(message))
      }
      return .err(.unexpectedError(ErrorI18NKeys.pinVerifyFailed))
    }
  }
}
