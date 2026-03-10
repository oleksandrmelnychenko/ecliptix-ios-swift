// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct NetworkProviderServices {

  let connectivityService: ConnectivityService
  let retryStrategy: RpcRetryStrategy
  let pendingRequestManager: PendingRequestManager

  init(
    connectivityService: ConnectivityService,
    retryStrategy: RpcRetryStrategy,
    pendingRequestManager: PendingRequestManager
  ) {
    self.connectivityService = connectivityService
    self.retryStrategy = retryStrategy
    self.pendingRequestManager = pendingRequestManager
  }
}

protocol ConnectivityService: Sendable {

  var isConnected: Bool { get }
  var connectionType: ConnectionType { get }

  func publishAsync(_ intent: ConnectivityIntent) async

  func observeConnectivity() -> AsyncStream<ConnectivityState>
}

enum ConnectivityState: Sendable {
  case connected(connectId: UInt32)
  case connecting(connectId: UInt32)
  case disconnected(reason: String?)
  case reconnecting(attempt: Int)
}

enum ConnectivityIntent: Sendable {
  case connecting(UInt32)
  case connected(UInt32)
  case disconnect(String?)
  case retry(attempt: Int)
}

enum ConnectionType: Sendable {
  case wifi
  case cellular
  case ethernet
  case none
}

protocol RpcRetryStrategy {

  func executeRpcOperation<T>(
    _ operation: @escaping (Int, CancellationToken) async throws -> Result<T, NetworkFailure>,
    operationName: String,
    connectId: UInt32,
    serviceType: RpcServiceType,
    maxRetries: Int?,
    cancellationToken: CancellationToken
  ) async -> Result<T, NetworkFailure>
}

final class CancellationToken: @unchecked Sendable {

  private var isCancelled: Bool = false
  private let lock = NSLock()
  static let none = CancellationToken()
  var cancelled: Bool {
    lock.lock()
    defer { lock.unlock() }

    return isCancelled
  }

  func cancel() {
    lock.lock()
    defer { lock.unlock() }

    isCancelled = true
  }
}

protocol PendingRequestManager {

  func addPendingRequest(key: String, request: PendingRequest)

  func removePendingRequest(_ key: String)

  func getPendingRequest(_ key: String) -> PendingRequest?

  func listPendingRequests() -> [PendingRequest]
}

struct PendingRequest: Sendable {

  let key: String
  let connectId: UInt32
  let exchangeType: PubKeyExchangeType
  let maxRetries: Int?
  let saveState: Bool
  let createdAt: Date

  init(
    key: String,
    connectId: UInt32,
    exchangeType: PubKeyExchangeType,
    maxRetries: Int? = nil,
    saveState: Bool = true,
    createdAt: Date = Date()
  ) {
    self.key = key
    self.connectId = connectId
    self.exchangeType = exchangeType
    self.maxRetries = maxRetries
    self.saveState = saveState
    self.createdAt = createdAt
  }
}
