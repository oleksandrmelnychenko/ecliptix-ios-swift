// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class PinRpcService {

  private let pipeline: SecureUnaryPipeline

  init(
    transport: EventGatewayTransport,
    secureSessionClient: any SecureSessionClient & NetworkOutageControlling,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService
  ) {
    self.pipeline = SecureUnaryPipeline(
      transport: transport,
      secureSessionClient: secureSessionClient,
      log: AppLogger.auth,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
  }

  func pinRegisterInit(
    request: PinRegisterInitRequest,
    connectId: UInt32
  ) async -> Result<PinRegisterInitResponse, RpcError> {
    await executeTypedUnary(
      serviceType: .pinRegisterInit, request: request, connectId: connectId,
      label: "PinRegisterInit")
  }

  func pinRegisterComplete(
    request: PinRegisterCompleteRequest,
    connectId: UInt32
  ) async -> Result<PinRegisterCompleteResponse, RpcError> {
    await executeTypedUnary(
      serviceType: .pinRegisterComplete, request: request, connectId: connectId,
      label: "PinRegisterComplete")
  }

  func pinVerifyInit(
    request: PinVerifyInitRequest,
    connectId: UInt32
  ) async -> Result<PinVerifyInitResponse, RpcError> {
    await executeTypedUnary(
      serviceType: .pinVerifyInit, request: request, connectId: connectId, label: "PinVerifyInit")
  }

  func pinVerifyFinalize(
    request: PinVerifyFinalizeRequest,
    connectId: UInt32
  ) async -> Result<PinVerifyFinalizeResponse, RpcError> {
    await executeTypedUnary(
      serviceType: .pinVerifyFinalize, request: request, connectId: connectId,
      label: "PinVerifyFinalize")
  }

  func pinDisable(
    request: PinDisableRequest,
    connectId: UInt32
  ) async -> Result<PinDisableResponse, RpcError> {
    await executeTypedUnary(
      serviceType: .pinDisable, request: request, connectId: connectId, label: "PinDisable")
  }

  private func executeTypedUnary<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    serviceType: RpcServiceType,
    request: Request,
    connectId: UInt32,
    label: String
  ) async -> Result<Response, RpcError> {
    AppLogger.auth.info("\(label): start connectId=\(connectId, privacy: .public)")
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      AppLogger.auth.error("\(label): serialize failed connectId=\(connectId, privacy: .public)")
      return .err(.serializationFailed("\(label) request"))
    }

    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: serviceType, plaintext: requestData, connectId: connectId)
    guard let decryptedPayload = decryptedResult.ok() else {
      AppLogger.auth.warning(
        "\(label): secure unary failed connectId=\(connectId, privacy: .public), error=\(decryptedResult.unwrapErr().logDescription, privacy: .public)"
      )
      return decryptedResult.propagateErr()
    }

    let response: Response
    do {
      response = try Response(serializedBytes: decryptedPayload)
    } catch {
      AppLogger.auth.error("\(label): parse failed connectId=\(connectId, privacy: .public)")
      return .err(.deserializationFailed("\(label) response: \(error.localizedDescription)"))
    }
    AppLogger.auth.info("\(label): success connectId=\(connectId, privacy: .public)")
    return .ok(response)
  }
}
