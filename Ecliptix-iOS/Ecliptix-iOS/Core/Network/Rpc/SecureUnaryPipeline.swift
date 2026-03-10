// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class SecureUnaryPipeline: @unchecked Sendable {

  private let transport: EventGatewayTransport
  private let secureSessionClient: any SecureSessionClient
  private let outageController: any NetworkOutageControlling
  private let log: Logger
  private let secureStorageService: SecureStorageService
  private let protocolStateStorage: ProtocolStateStorage
  private let identityService: IdentityService

  private static let maxAttempts = AppConstants.Network.maxRetryAttempts
  private static let initialDelay: TimeInterval = 0.5
  private static let maxDelay: TimeInterval = 2.0
  private static let nanosecondsPerSecond: UInt64 = 1_000_000_000

  init(
    transport: EventGatewayTransport,
    secureSessionClient: any SecureSessionClient & NetworkOutageControlling,
    log: Logger,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService
  ) {
    self.transport = transport
    self.secureSessionClient = secureSessionClient
    self.outageController = secureSessionClient
    self.log = log
    self.secureStorageService = secureStorageService
    self.protocolStateStorage = protocolStateStorage
    self.identityService = identityService
  }

  func executeSecureRpc<Req: SwiftProtobuf.Message, Resp: SwiftProtobuf.Message>(
    serviceType: RpcServiceType,
    request: Req,
    connectId: UInt32
  ) async -> Result<Resp, RpcError> {
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      return .err(.serializationFailed("\(serviceType.rawValue) request"))
    }
    let result = await executeSecureUnary(
      serviceType: serviceType,
      plaintext: requestData,
      connectId: connectId
    )
    guard let payload = result.ok() else {
      return result.propagateErr()
    }
    do {
      return .ok(try Resp(serializedBytes: payload))
    } catch {
      return .err(
        .deserializationFailed("\(serviceType.rawValue) response: \(error.localizedDescription)"))
    }
  }

  func executeSecureUnary(
    serviceType: RpcServiceType,
    plaintext: Data,
    connectId: UInt32
  ) async -> Result<Data, RpcError> {
    var lastError: RpcError = .unexpected("Unknown secure unary error")
    var context = RpcRequestContext.createNew()
    for attempt in 1...Self.maxAttempts {
      log.debug(
        "Secure unary: attempt=\(context.attemptNumber, privacy: .public), requestId=\(context.requestId.uuidString, privacy: .public), service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), requestBytes=\(plaintext.count, privacy: .public), reinit=\(context.reinitAttempted, privacy: .public)"
      )
      let singleAttemptResult = await executeSecureUnaryOnce(
        serviceType: serviceType,
        plaintext: plaintext,
        connectId: connectId
      )
      if singleAttemptResult.isOk {
        outageController.exitOutage()
        return singleAttemptResult
      }

      let error = singleAttemptResult.unwrapErr()
      lastError = error
      let shouldRetry = attempt < Self.maxAttempts && error.isRetryable
      if !shouldRetry {
        outageController.exitOutage()
        log.error(
          "Secure unary: final failure requestId=\(context.requestId.uuidString, privacy: .public), attempt=\(context.attemptNumber, privacy: .public), service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(error.logDescription, privacy: .public)"
        )
        return .err(error)
      }
      outageController.clearExhaustedOperations()
      if error.requiresStateCleanup {
        _ = await protocolStateStorage.deleteState(connectId: String(connectId))
        secureSessionClient.clearConnection(connectId: connectId)
      }
      log.warning(
        "Secure unary: retrying requestId=\(context.requestId.uuidString, privacy: .public), attempt=\(context.attemptNumber, privacy: .public), service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), error=\(error.logDescription, privacy: .public)"
      )
      context.markReinitAttempted()
      _ = await recoverSecureSession(connectId: connectId)
      context.incrementAttempt()
      let delay = computeSecureUnaryDelay(attempt: attempt)
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * Double(Self.nanosecondsPerSecond)))
      } catch {
        return .err(.unexpected("Secure unary request cancelled"))
      }
    }
    return .err(lastError)
  }

  private func executeSecureUnaryOnce(
    serviceType: RpcServiceType,
    plaintext: Data,
    connectId: UInt32
  ) async -> Result<Data, RpcError> {
    let sessionResult = await resolveSessionForSecureUnary(connectId: connectId)
    guard let session = sessionResult.ok() else {
      return sessionResult.propagateErr()
    }

    let requestEnvelope: EventEnvelope
    do {
      requestEnvelope = try await transport.requestEnvelope(
        serviceType: serviceType,
        rawPayload: plaintext,
        connectId: connectId
      )
    } catch {
      return .err(
        .serializationFailed("secure request envelope: \(error.localizedDescription)"))
    }

    let requestEnvelopeData: Data
    do {
      requestEnvelopeData = try requestEnvelope.serializedData()
    } catch {
      return .err(
        .serializationFailed("secure request envelope body: \(error.localizedDescription)"))
    }

    let encryptedRequest: Data
    do {
      encryptedRequest = try session.encrypt(
        plaintext: requestEnvelopeData,
        envelopeType: .request,
        envelopeId: UInt32.random(in: 1...UInt32.max)
      )
    } catch let error as ProtocolError {
      return .err(.encryptionFailed(error.message))
    } catch {
      return .err(.encryptionFailed(error.localizedDescription))
    }

    let protoSecureRequest: ProtoSecureEnvelope
    do {
      protoSecureRequest = try ProtoSecureEnvelope(serializedBytes: encryptedRequest)
    } catch {
      return .err(.serializationFailed("secure request envelope: \(error.localizedDescription)"))
    }

    let networkResult = await transport.unary(
      serviceType: serviceType,
      payload: protoSecureRequest,
      connectId: connectId
    )
    guard let response = networkResult.ok() else {
      return networkResult.propagateErr()
    }

    let secureResponseData: Data
    do {
      let protoSecureResponse = try ProtoSecureEnvelope(serializedBytes: response.payload)
      secureResponseData = try protoSecureResponse.serializedData()
    } catch {
      return .err(.deserializationFailed("secure response envelope: \(error.localizedDescription)"))
    }
    do {
      try NativeProtocolSession.validateEnvelope(secureResponseData)
    } catch let error as ProtocolError {
      return .err(.decryptionFailed("invalid envelope: \(error.message)"))
    } catch {
      return .err(.decryptionFailed("invalid envelope: \(error.localizedDescription)"))
    }

    let decryptedEnvelopeBytes: Data
    do {
      let decrypted = try session.decrypt(secureResponseData)
      decryptedEnvelopeBytes = decrypted.plaintext
    } catch let error as ProtocolError {
      return .err(.decryptionFailed(error.message))
    } catch {
      return .err(.decryptionFailed(error.localizedDescription))
    }
    let innerResponse: EventEnvelope
    do {
      innerResponse = try EventEnvelope(serializedBytes: decryptedEnvelopeBytes)
    } catch {
      return .err(
        .deserializationFailed("secure response envelope body: \(error.localizedDescription)"))
    }
    if let serverError = GatewayTransportFactory.mapOutcome(innerResponse.metadata) {
      log.warning(
        "Secure unary: server outcome error service=\(serviceType.rawValue, privacy: .public), connectId=\(connectId, privacy: .public), outcome=\(serverError.logDescription, privacy: .public)"
      )
      return .err(serverError)
    }
    return .ok(innerResponse.payload)
  }

  private func resolveSessionForSecureUnary(
    connectId: UInt32
  ) async -> Result<NativeProtocolSession, RpcError> {
    if let session = secureSessionClient.activeSession(connectId: connectId) {
      log.debug("Secure session: hit connectId=\(connectId, privacy: .public)")
      return .ok(session)
    }
    log.warning("Secure session: miss connectId=\(connectId, privacy: .public), recovering")
    let recoverResult = await recoverSecureSession(connectId: connectId)
    guard recoverResult.isOk else {
      return .err(.sessionNotFound)
    }
    guard let session = secureSessionClient.activeSession(connectId: connectId) else {
      return .err(.sessionNotFound)
    }
    log.info("Secure session: recovered connectId=\(connectId, privacy: .public)")
    return .ok(session)
  }

  private func recoverSecureSession(connectId: UInt32) async -> Result<Unit, RpcError> {
    log.info("Secure session recovery: start connectId=\(connectId, privacy: .public)")
    guard let settings = secureStorageService.settings else {
      log.warning(
        "Secure session recovery: missing settings, fresh handshake connectId=\(connectId, privacy: .public)"
      )
      return await establishFreshSecrecyChannel(
        connectId: connectId,
        deviceId: NetworkConfiguration.default.deviceId,
        appInstanceId: NetworkConfiguration.default.appInstanceId
      )
    }

    let restored = await tryRestorePersistedSession(connectId: connectId, settings: settings)
    if restored {
      log.info(
        "Secure session recovery: restored from persisted state connectId=\(connectId, privacy: .public)"
      )
      return .ok(Unit.value)
    }
    log.warning(
      "Secure session recovery: persisted restore failed, fresh handshake connectId=\(connectId, privacy: .public)"
    )
    return await establishFreshSecrecyChannel(
      connectId: connectId,
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId
    )
  }

  private func tryRestorePersistedSession(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Bool {
    guard let accountId = settings.currentAccountId else {
      return false
    }

    let accountIdData = accountId.protobufBytes
    let loadStateResult = await protocolStateStorage.loadState(
      connectId: String(connectId),
      accountId: accountIdData
    )
    guard let (sealedState, minExternalCounter) = loadStateResult.ok() else {
      return false
    }
    secureSessionClient.clearConnection(connectId: connectId)
    guard let membershipId = settings.membership?.membershipId,
      let sealKey = await deriveSealKey(accountId: accountId, membershipId: membershipId)
    else {
      _ = await protocolStateStorage.deleteState(connectId: String(connectId))
      secureSessionClient.clearConnection(connectId: connectId)
      return false
    }

    let restoreResult = await secureSessionClient.restoreSecrecyChannel(
      sealedState: sealedState,
      connectId: connectId,
      settings: settings,
      sealKey: sealKey,
      minExternalCounter: minExternalCounter
    )
    if restoreResult.isOk {
      return true
    }
    _ = await protocolStateStorage.deleteState(connectId: String(connectId))
    secureSessionClient.clearConnection(connectId: connectId)
    return false
  }

  private func deriveSealKey(accountId: UUID, membershipId: UUID) async -> Data? {
    await identityService.deriveSealedStateKey(
      forAccountId: accountId,
      membershipId: membershipId
    ).ok()
  }

  private func establishFreshSecrecyChannel(
    connectId: UInt32,
    deviceId: UUID,
    appInstanceId: UUID
  ) async -> Result<Unit, RpcError> {
    log.info(
      "Secure session recovery: fresh handshake start connectId=\(connectId, privacy: .public), deviceId=\(deviceId.uuidString, privacy: .private(mask: .hash)), appId=\(appInstanceId.uuidString, privacy: .private(mask: .hash))"
    )
    secureSessionClient.initiateProtocol(
      deviceId: deviceId,
      appInstanceId: appInstanceId,
      connectId: connectId
    )
    let establishResult = await secureSessionClient.establishSecrecyChannel(connectId: connectId)
    guard establishResult.isOk else {
      let errorMsg = establishResult.err() ?? ""
      log.error(
        "Secure session recovery: fresh handshake failed connectId=\(connectId, privacy: .public), error=\(errorMsg, privacy: .public)"
      )
      return .err(.sessionRecoveryFailed(errorMsg))
    }
    log.info(
      "Secure session recovery: fresh handshake success connectId=\(connectId, privacy: .public)")
    return .ok(Unit.value)
  }

  private func computeSecureUnaryDelay(attempt: Int) -> TimeInterval {
    let exponentialDelay = Self.initialDelay * pow(2.0, Double(attempt - 1))
    let capped = min(exponentialDelay, Self.maxDelay)
    let jitter = capped * Double.random(in: -0.25...0.25)
    return max(0.1, capped + jitter)
  }
}
