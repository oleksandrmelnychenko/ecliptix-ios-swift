// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class ConnectivityObserver {

  private let connectivityService: ConnectivityService
  private let networkProvider: NetworkProvider
  private var observationTask: Task<Void, Never>?

  init(
    connectivityService: ConnectivityService,
    networkProvider: NetworkProvider
  ) {
    self.connectivityService = connectivityService
    self.networkProvider = networkProvider
  }

  deinit {
    observationTask?.cancel()
  }

  func start() {
    observationTask?.cancel()
    observationTask = Task { [weak self] in
      guard let self else { return }
      for await state in connectivityService.observeConnectivity() {
        if case .connected = state {
          await networkProvider.retryPendingSecrecyChannelRequests()
        }
      }
    }
  }

  func stop() {
    observationTask?.cancel()
    observationTask = nil
  }
}
