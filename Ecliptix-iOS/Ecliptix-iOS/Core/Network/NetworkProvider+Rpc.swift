import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftProtobuf
import os

extension NetworkProvider {

  func sendEstablishChannelRpcRaw(
    connectId: UInt32,
    handshakePayload: Data,
    exchangeType: PubKeyExchangeType
  ) async -> Result<Data, RpcError> {
    do {
      let service = try rpcServiceManager.getSecrecyChannelService()
      return await service.establishChannelRaw(
        connectId: connectId,
        handshakePayload: handshakePayload,
        exchangeType: exchangeType,
        cancellationToken: .none
      )
    } catch {
      return .err(.unexpected("RPC service not configured: \(error.localizedDescription)"))
    }
  }

  func registerDeviceRpc(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Result<Unit, RpcError> {
    AppLogger.network.info("RegisterDevice RPC: start connectId=\(connectId, privacy: .public)")
    let device = Device(
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId,
      deviceType: .mobile,
      platform: "iOS",
      osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
      appVersion: "1.0.0"
    )
    let sessionResult = nativeSessions.get(connectId: connectId)
    guard case .ok(let session) = sessionResult else {
      AppLogger.network.warning(
        "RegisterDevice RPC: missing session connectId=\(connectId, privacy: .public)")
      return .err(.sessionNotFound)
    }

    var protoDevice = ProtoDevice()
    protoDevice.deviceID = device.deviceId.protobufBytes
    protoDevice.applicationInstanceID = device.appInstanceId.protobufBytes
    protoDevice.deviceType = .mobile
    let deviceBytes: Data
    do {
      deviceBytes = try protoDevice.serializedData()
    } catch {
      return .err(.serializationFailed("device registration request"))
    }
    do {
      let requestEnvelopeId = UInt32.random(in: 1...UInt32.max)
      AppLogger.security.debug(
        "RegisterDevice RPC: encrypting payload connectId=\(connectId, privacy: .public), envelopeId=\(requestEnvelopeId, privacy: .public), payloadBytes=\(deviceBytes.count, privacy: .public)"
      )
      let encryptedPayload = try session.encrypt(
        plaintext: deviceBytes,
        envelopeType: .request,
        envelopeId: requestEnvelopeId,
        correlationId: UUID().uuidString
      )
      let service = try rpcServiceManager.getDeviceProvisioningService()
      let result = await service.registerDevice(
        device: device,
        encryptedPayload: encryptedPayload,
        cancellationToken: .none
      )
      guard let encryptedResponseEnvelope = result.ok() else {
        let rpcError = result.unwrapErr()
        AppLogger.network.warning(
          "RegisterDevice RPC: transport failure connectId=\(connectId, privacy: .public), error=\(rpcError.logDescription, privacy: .public)"
        )
        return .err(rpcError)
      }
      try NativeProtocolSession.validateEnvelope(encryptedResponseEnvelope)
      let decrypted = try session.decrypt(encryptedResponseEnvelope)
      guard
        let response = try? ProtoDeviceRegistrationResponse(
          serializedBytes: decrypted.plaintext
        )
      else {
        return .err(.deserializationFailed("device registration response"))
      }
      switch response.result {
      case .invalidRequest:
        AppLogger.network.warning(
          "RegisterDevice RPC: invalid request connectId=\(connectId, privacy: .public), message=\(response.message, privacy: .public)"
        )
        return .err(.serverError(code: "device.invalid_request", message: response.message))
      case .internalError:
        AppLogger.network.warning(
          "RegisterDevice RPC: server internal error connectId=\(connectId, privacy: .public), message=\(response.message, privacy: .public)"
        )
        return .err(.serverError(code: "device.internal_error", message: response.message))
      default:
        AppLogger.network.info(
          "RegisterDevice RPC: success connectId=\(connectId, privacy: .public)")
        return .ok(Unit.value)
      }
    } catch let error as ProtocolError {
      AppLogger.security.warning(
        "RegisterDevice RPC: protocol encryption/decryption error connectId=\(connectId, privacy: .public), error=\(error.message, privacy: .public)"
      )
      return .err(.encryptionFailed("device data: \(error.message)"))
    } catch {
      AppLogger.network.error(
        "RegisterDevice RPC: unexpected error connectId=\(connectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.unexpected("RPC service error: \(error.localizedDescription)"))
    }
  }
}
