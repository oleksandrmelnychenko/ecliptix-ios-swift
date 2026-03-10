// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension NetworkProvider {

  func executeUnaryRequest(
    connectId: UInt32,
    serviceType: RpcServiceType,
    plainBuffer: Data,
    onCompleted: @escaping (Data) async -> Result<Unit, NetworkFailure>,
    allowDuplicates: Bool = false,
    cancellationToken: CancellationToken = .none,
    waitForRecovery: Bool = true,
    requestContext: RpcRequestContext? = nil
  ) async -> Result<Unit, NetworkFailure> {
    await makeEncryptedRequestExecutor().execute(
      request: ServiceRequestParams(
        connectId: connectId,
        serviceType: serviceType,
        plainBuffer: plainBuffer,
        flowType: .single,
        onCompleted: onCompleted,
        requestContext: requestContext,
        allowDuplicateRequests: allowDuplicates,
        waitForRecovery: waitForRecovery,
        cancellationToken: cancellationToken,
        exchangeType: .dataCenterEphemeralConnect
      )
    )
  }

  func executeReceiveStreamRequest(
    connectId: UInt32,
    serviceType: RpcServiceType,
    plainBuffer: Data,
    onStreamItem: @escaping (Data) async -> Result<Unit, NetworkFailure>,
    allowDuplicates: Bool = false,
    cancellationToken: CancellationToken = .none,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) async -> Result<Unit, NetworkFailure> {
    await makeEncryptedRequestExecutor().execute(
      request: ServiceRequestParams(
        connectId: connectId,
        serviceType: serviceType,
        plainBuffer: plainBuffer,
        flowType: .receiveStream,
        onCompleted: onStreamItem,
        requestContext: nil,
        allowDuplicateRequests: allowDuplicates,
        waitForRecovery: true,
        cancellationToken: cancellationToken,
        exchangeType: exchangeType
      )
    )
  }

  private func makeEncryptedRequestExecutor() -> NetworkEncryptedRequestExecutor {
    NetworkEncryptedRequestExecutor(
      sessionRuntime: nativeSessions,
      rpcServiceManager: rpcServiceManager,
      requestRegistry: runtime.requestRegistry,
      outageState: runtime.outageState,
      recoverSession: { [self] connectId in
        await establishSecrecyChannel(connectId: connectId)
      },
      clearConnection: { [self] connectId in
        clearConnection(connectId: connectId)
      },
      retryPendingRequests: { [self] in
        await retryPendingSecrecyChannelRequests()
      }
    )
  }
}
