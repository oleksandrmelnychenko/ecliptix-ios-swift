// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

protocol SecureSessionClient: AnyObject {

  func activeSession(connectId: UInt32) -> NativeProtocolSession?

  func clearConnection(connectId: UInt32)

  func ensureProtocolForStreaming() async -> Result<UInt32, String>

  func restoreSecrecyChannel(
    sealedState: Data,
    connectId: UInt32,
    settings: ApplicationInstanceSettings,
    sealKey: Data,
    minExternalCounter: UInt64
  ) async -> Result<Unit, String>

  func establishSecrecyChannel(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType
  ) async -> Result<Unit, String>

  @discardableResult
  func initiateProtocol(
    deviceId: UUID,
    appInstanceId: UUID,
    connectId: UInt32
  ) -> Bool

  func recreateProtocolWithMasterKey(
    masterKey: Data,
    membershipId: UUID,
    accountId: UUID,
    connectId: UInt32
  ) async -> Result<Unit, String>

  func persistSessionState(
    connectId: UInt32,
    accountId: Data,
    sealKey: Data,
    externalCounter: UInt64
  ) async -> Result<Unit, String>

  func getServerPublicKey(connectId: UInt32) async -> Result<Data, NetworkFailure>
}

extension SecureSessionClient {

  func establishSecrecyChannel(connectId: UInt32) async -> Result<Unit, String> {
    await establishSecrecyChannel(connectId: connectId, exchangeType: .dataCenterEphemeralConnect)
  }
}

protocol ApplicationBootstrapClient: SecureSessionClient {

  func registerDeviceRpc(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Result<Unit, RpcError>

  func setCountry(_ country: String)
}

protocol SecureStreamingRequestExecuting: AnyObject {

  func executeReceiveStreamRequest(
    connectId: UInt32,
    serviceType: RpcServiceType,
    plainBuffer: Data,
    onStreamItem: @escaping (Data) async -> Result<Unit, NetworkFailure>,
    allowDuplicates: Bool,
    cancellationToken: CancellationToken,
    exchangeType: PubKeyExchangeType
  ) async -> Result<Unit, NetworkFailure>
}

protocol NetworkOutageControlling: AnyObject {

  func exitOutage()

  func clearExhaustedOperations()
}

protocol PendingLogoutTransportProviding: AnyObject {

  func configure(networkConfiguration: NetworkConfiguration, metadataProvider: MetadataProvider)
    throws

  func getTransport() throws -> EventGatewayTransport

  func getNetworkConfiguration() throws -> NetworkConfiguration
}

extension NetworkProvider: SecureSessionClient, ApplicationBootstrapClient,
  SecureStreamingRequestExecuting, NetworkOutageControlling
{

  func activeSession(connectId: UInt32) -> NativeProtocolSession? {
    nativeSessions.get(connectId: connectId).ok()
  }
}

extension RpcServiceManager: PendingLogoutTransportProviding {}
