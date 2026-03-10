// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os.log

final class RpcServiceManager: @unchecked Sendable {

  static let shared: RpcServiceManager = RpcServiceManager()
  private var transport: EventGatewayTransport?
  private var channelProvider: GrpcChannelProvider?
  private var networkConfiguration: NetworkConfiguration?
  private var _secrecyChannelService: SecrecyChannelRpcService?
  private var _deviceProvisioningService: DeviceProvisioningRpcService?
  private let lock: NSLock = NSLock()

  private init() {}

  func configure(networkConfiguration: NetworkConfiguration, metadataProvider: MetadataProvider)
    throws
  {
    lock.lock()
    defer { lock.unlock() }

    guard !networkConfiguration.baseURL.isEmpty else {
      throw NSError(
        domain: "RpcServiceManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Endpoint cannot be empty"]
      )
    }

    let provider = GrpcChannelProvider(configuration: networkConfiguration)
    let gateway = EventGatewayTransport(
      channelProvider: provider,
      metadataProvider: metadataProvider
    )
    self.channelProvider = provider
    self.networkConfiguration = networkConfiguration
    self.transport = gateway
    self._secrecyChannelService = SecrecyChannelRpcService(transport: gateway)
    self._deviceProvisioningService = DeviceProvisioningRpcService(transport: gateway)
    AppLogger.network.info(
      "RpcServiceManager: configured host=\(networkConfiguration.baseURL, privacy: .public), port=\(networkConfiguration.port, privacy: .public), tls=\(networkConfiguration.useTLS, privacy: .public)"
    )
  }

  func getSecrecyChannelService() throws -> SecrecyChannelRpcService {
    lock.lock()
    defer { lock.unlock() }

    guard let service = _secrecyChannelService else {
      throw NSError(
        domain: "RpcServiceManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "RpcServiceManager not configured"]
      )
    }
    return service
  }

  func getDeviceProvisioningService() throws -> DeviceProvisioningRpcService {
    lock.lock()
    defer { lock.unlock() }

    guard let service = _deviceProvisioningService else {
      throw NSError(
        domain: "RpcServiceManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "RpcServiceManager not configured"]
      )
    }
    return service
  }

  func getTransport() throws -> EventGatewayTransport {
    lock.lock()
    defer { lock.unlock() }

    guard let transport else {
      throw NSError(
        domain: "RpcServiceManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "RpcServiceManager not configured"]
      )
    }
    return transport
  }

  func getNetworkConfiguration() throws -> NetworkConfiguration {
    lock.lock()
    defer { lock.unlock() }

    guard let networkConfiguration else {
      throw NSError(
        domain: "RpcServiceManager",
        code: -1,
        userInfo: [NSLocalizedDescriptionKey: "RpcServiceManager network configuration unavailable"]
      )
    }
    return networkConfiguration
  }

  func unary(
    serviceType: RpcServiceType,
    payload: ProtoSecureEnvelope,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) async -> Result<EventEnvelope, RpcError> {
    let gateway: EventGatewayTransport? = lock.withLock { transport }
    guard let gateway else {
      return .err(.unexpected("RpcServiceManager not configured"))
    }
    return await gateway.unary(
      serviceType: serviceType,
      payload: payload,
      exchangeType: exchangeType
    )
  }

  func serverStream(
    serviceType: RpcServiceType,
    payload: ProtoSecureEnvelope,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect,
    onMessage: @escaping (EventEnvelope) async -> Void
  ) async -> Result<Unit, RpcError> {
    let gateway: EventGatewayTransport? = lock.withLock { transport }
    guard let gateway else {
      return .err(.unexpected("RpcServiceManager not configured"))
    }
    return await gateway.serverStream(
      serviceType: serviceType,
      payload: payload,
      exchangeType: exchangeType,
      onMessage: onMessage
    )
  }

  var isConfigured: Bool {
    lock.lock()
    defer { lock.unlock() }

    return transport != nil
  }

  func shutdown() async {
    AppLogger.network.info("RpcServiceManager: shutdown initiated")
    let provider: GrpcChannelProvider? = lock.withLock {
      let p = channelProvider
      transport = nil
      channelProvider = nil
      networkConfiguration = nil
      _secrecyChannelService = nil
      _deviceProvisioningService = nil
      return p
    }
    await provider?.shutdown()
    AppLogger.network.info("RpcServiceManager: shutdown complete")
  }
}
