import Combine
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Network

final class ReachabilityService: ConnectivityService {

  private let monitor: NWPathMonitor
  private let queue: DispatchQueue
  private let lock = NSLock()
  private var _currentPath: NWPath?
  private var _isConnected: Bool = false
  private var _connectionType: ConnectionType = .none
  private var connectivitySubject = PassthroughSubject<ConnectivityState, Never>()
  var isConnected: Bool {
    lock.withLock { _isConnected }
  }

  var connectionType: ConnectionType {
    lock.withLock { _connectionType }
  }

  init(queue: DispatchQueue = DispatchQueue(label: "com.ecliptix.reachability")) {
    self.monitor = NWPathMonitor()
    self.queue = queue
    setupMonitoring()
  }

  deinit {
    monitor.cancel()
  }

  func publishAsync(_ intent: ConnectivityIntent) async {
    switch intent {
    case .connecting(let connectId):
      connectivitySubject.send(.connecting(connectId: connectId))
    case .connected(let connectId):
      connectivitySubject.send(.connected(connectId: connectId))
    case .disconnect(let reason):
      connectivitySubject.send(.disconnected(reason: reason))
    case .retry(let attempt):
      connectivitySubject.send(.reconnecting(attempt: attempt))
    }
  }

  func observeConnectivity() -> AsyncStream<ConnectivityState> {
    AsyncStream { continuation in
      let cancellable = connectivitySubject.sink { state in
        continuation.yield(state)
      }
      continuation.onTermination = { _ in
        cancellable.cancel()
      }
    }
  }

  private func setupMonitoring() {
    monitor.pathUpdateHandler = { [weak self] path in
      self?.handlePathUpdate(path)
    }
    monitor.start(queue: queue)
  }

  private func handlePathUpdate(_ path: NWPath) {
    let intent: ConnectivityIntent? = lock.withLock {
      _currentPath = path
      let wasConnected = _isConnected
      _isConnected = path.status == .satisfied
      _connectionType = determineConnectionType(from: path)
      if !wasConnected && _isConnected {
        return .connected(0)
      } else if wasConnected && !_isConnected {
        return .disconnect("Network unavailable")
      }
      return nil
    }
    if let intent {
      Task { @MainActor in await publishAsync(intent) }
    }
  }

  private func determineConnectionType(from path: NWPath) -> ConnectionType {
    if path.usesInterfaceType(.wifi) {
      return .wifi
    } else if path.usesInterfaceType(.cellular) {
      return .cellular
    } else if path.usesInterfaceType(.wiredEthernet) {
      return .ethernet
    } else {
      return .none
    }
  }
}
