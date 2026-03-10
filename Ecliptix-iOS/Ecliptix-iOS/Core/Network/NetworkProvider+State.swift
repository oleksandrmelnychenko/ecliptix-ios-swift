// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension NetworkProvider {

  func initializeNetworkProvider() async -> Result<Unit, NetworkFailure> {
    let settingsResult = await loadApplicationInstanceSettings()
    guard case .ok(let settings) = settingsResult else {
      return settingsResult.propagateErr()
    }
    runtime.instanceSettingsStore.set(settings)
    return .ok(.value)
  }

  func cleanupSession(connectId: UInt32) async {
    nativeSessions.remove(connectId: connectId)
    _ = await dependencies.stateStorage.deleteSessionState(for: connectId)
  }

  func cleanupAllSessions() async {
    let statesResult = await dependencies.stateStorage.listSessionStates()
    if case .ok(let states) = statesResult {
      for state in states {
        _ = await dependencies.stateStorage.deleteSessionState(for: state.connectId)
      }
    }
    nativeSessions.disposeAll()
  }

  func cleanupFailedAuthentication(connectId: UInt32) {
    nativeSessions.clearHandshakeInitiator(connectId: connectId)
    nativeSessions.clearServerPreKeyBundle(connectId: connectId)
    nativeSessions.clearServerNonce(connectId: connectId)
    nativeSessions.clearServerPublicKey(connectId: connectId)
  }

  func dispose() async {
    runtime.requestRegistry.cancelAll()
    nativeSessions.disposeAll()
    _ = await dependencies.stateStorage.deleteAllSessionStates()
    await rpcServiceManager.shutdown()
  }
}

extension NetworkProvider {

  fileprivate func loadApplicationInstanceSettings() async -> Result<
    NetworkProviderInstanceSettings, NetworkFailure
  > {
    let metadata = dependencies.metadataProvider
    let settings = NetworkProviderInstanceSettings(
      deviceId: metadata.deviceId,
      appInstanceId: metadata.appInstanceId,
      platform: metadata.platform,
      country: "US",
      culture: metadata.culture,
      appVersion: metadata.appVersion,
      osVersion: metadata.osVersion
    )
    return .ok(settings)
  }
}
