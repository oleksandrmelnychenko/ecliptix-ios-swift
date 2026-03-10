// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class ProfileRpcService {

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

  func profileLookup(
    accountId: UUID,
    connectId: UInt32
  ) async -> Result<AccountProfile?, RpcError> {
    var request = ProfileLookupRequest()
    request.currentAccountID = accountId.protobufBytes
    request.byAccountID = accountId.protobufBytes
    let result: Result<ProfileLookupResponse, RpcError> = await executeTypedUnary(
      serviceType: .profileLookup, request: request, connectId: connectId, label: "ProfileLookup")
    guard let response = result.ok() else { return result.propagateErr() }
    return .ok(response.hasProfile ? response.profile : nil)
  }

  func profileLookupByMobile(
    mobileNumber: String,
    currentAccountId: UUID,
    connectId: UInt32
  ) async -> Result<AccountProfile?, RpcError> {
    var request = ProfileLookupRequest()
    request.currentAccountID = currentAccountId.protobufBytes
    request.byMobileNumber = mobileNumber
    let result: Result<ProfileLookupResponse, RpcError> = await executeTypedUnary(
      serviceType: .profileLookup, request: request, connectId: connectId,
      label: "ProfileLookupByMobile")
    guard let response = result.ok() else { return result.propagateErr() }
    return .ok(response.hasProfile ? response.profile : nil)
  }

  func profileNameAvailability(
    profileName: String,
    connectId: UInt32
  ) async -> Result<ProfileNameAvailabilityResult, RpcError> {
    var request = ProfileNameAvailabilityRequest()
    request.profileName = profileName
    let result: Result<ProfileNameAvailabilityResponse, RpcError> = await executeTypedUnary(
      serviceType: .profileNameAvailability, request: request, connectId: connectId,
      label: "ProfileNameAvailability")
    guard let response = result.ok() else { return result.propagateErr() }
    return .ok(
      ProfileNameAvailabilityResult(isAvailable: response.isAvailable, reason: response.reason))
  }

  func profileUpsert(
    accountId: UUID,
    profileName: String,
    displayName: String,
    connectId: UInt32
  ) async -> Result<Unit, RpcError> {
    var request = ProfileUpsertRequest()
    request.accountID = accountId.protobufBytes
    request.profileName = profileName
    request.displayName = displayName
    let result: Result<ProfileUpsertResponse, RpcError> = await executeTypedUnary(
      serviceType: .profileUpsert, request: request, connectId: connectId, label: "ProfileUpsert")
    guard let response = result.ok() else { return result.propagateErr() }
    guard response.isSuccess else {
      return .err(.serverError(code: "", message: "Profile update was not accepted by the server"))
    }
    return .ok(Unit.value)
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
