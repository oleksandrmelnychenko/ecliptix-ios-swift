// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

final class PendingLogoutCoordinator {

  private let secureStorage: SecureStorageService
  private let sessionBootstrap: SessionBootstrapService
  private let pendingLogoutStorage: PendingLogoutStorage
  private let pendingLogoutTransportProvider: any PendingLogoutTransportProviding

  init(
    secureStorage: SecureStorageService,
    sessionBootstrap: SessionBootstrapService,
    pendingLogoutStorage: PendingLogoutStorage,
    pendingLogoutTransportProvider: any PendingLogoutTransportProviding
  ) {
    self.secureStorage = secureStorage
    self.sessionBootstrap = sessionBootstrap
    self.pendingLogoutStorage = pendingLogoutStorage
    self.pendingLogoutTransportProvider = pendingLogoutTransportProvider
  }

  func processPendingLogouts(connectId: UInt32) async {
    guard let settings = secureStorage.settings,
      let membership = settings.membership
    else {
      await processPendingLogoutRequests(connectId: connectId)
      return
    }

    let hasProof = await secureStorage.hasRevocationProof(for: membership.membershipId)
    if hasProof {
      await sessionBootstrap.handleRevokedSession(
        connectId: connectId,
        accountId: settings.currentAccountId,
        membershipId: membership.membershipId
      )
      return
    }
    await processPendingLogoutRequests(connectId: connectId)
  }

  func processPendingLogoutRequests(connectId: UInt32) async {
    guard pendingLogoutStorage.hasPendingLogout else {
      return
    }
    AppLogger.auth.info("[INIT] Found pending logout request, processing on startup")
    guard let transport = resolvePendingLogoutTransport() else {
      AppLogger.auth.warning("[INIT] Cannot process pending logout: transport unavailable")
      return
    }

    let processor = PendingLogoutProcessor(
      pendingStorage: pendingLogoutStorage,
      transport: transport
    )
    await processor.processPendingLogout(connectId: connectId)
  }

  private func resolvePendingLogoutTransport() -> EventGatewayTransport? {
    if let transport = try? pendingLogoutTransportProvider.getTransport() {
      return transport
    }
    guard let pendingRecord = pendingLogoutStorage.getPendingLogoutRecord() else {
      AppLogger.auth.warning(
        "[INIT] Cannot configure pending logout transport: pending logout record unavailable")
      return nil
    }
    guard let networkConfiguration = pendingRecord.networkConfiguration else {
      AppLogger.auth.warning(
        "[INIT] Cannot configure pending logout transport: pending network configuration unavailable"
      )
      return nil
    }
    let metadataProvider = DefaultMetadataProvider(
      deviceId: secureStorage.settings?.deviceId ?? NetworkConfiguration.default.deviceId,
      appInstanceId: secureStorage.settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    )
    do {
      try pendingLogoutTransportProvider.configure(
        networkConfiguration: networkConfiguration,
        metadataProvider: metadataProvider
      )
      return try pendingLogoutTransportProvider.getTransport()
    } catch {
      AppLogger.auth.warning(
        "[INIT] Failed to configure pending logout transport: \(error.localizedDescription, privacy: .public)"
      )
      return nil
    }
  }
}
