// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class PendingLogoutProcessor {

  private let pendingStorage: PendingLogoutStorage
  private let transport: EventGatewayTransport

  init(
    pendingStorage: PendingLogoutStorage,
    transport: EventGatewayTransport
  ) {
    self.pendingStorage = pendingStorage
    self.transport = transport
  }

  func processPendingLogout(connectId: UInt32) async {
    guard let requestData = pendingStorage.getPendingLogout() else {
      return
    }
    AppLogger.auth.info(
      "[LOGOUT-RETRY] Processing pending logout, connectId=\(connectId, privacy: .public), bytes=\(requestData.count, privacy: .public)"
    )
    guard let logoutRequest = decodePendingLogoutRequest(requestData) else {
      AppLogger.auth.warning(
        "[LOGOUT-RETRY] Failed to deserialize pending logout request, clearing")
      pendingStorage.clearPendingLogout()
      return
    }

    let sendResult = await sendAnonymousLogout(request: logoutRequest)
    if sendResult {
      AppLogger.auth.info("[LOGOUT-RETRY] Pending logout sent successfully")
      pendingStorage.clearPendingLogout()
    } else {
      AppLogger.auth.warning(
        "[LOGOUT-RETRY] Pending logout send failed, will retry on next startup")
    }
  }

  private func sendAnonymousLogout(request: LogoutRequest) async -> Bool {
    let result = await transport.unary(
      serviceType: .anonymousLogout,
      payload: request
    )
    switch result {
    case .ok(let response):
      if let logoutResponse = try? LogoutResponse(serializedBytes: response.payload) {
        AppLogger.auth.info(
          "[LOGOUT-RETRY] Server response result=\(logoutResponse.result.rawValue, privacy: .public)"
        )
      }
      return true
    case .err(let error):
      AppLogger.auth.warning(
        "[LOGOUT-RETRY] Anonymous logout failed: \(error, privacy: .public)"
      )
      return false
    }
  }

  private func decodePendingLogoutRequest(_ data: Data) -> LogoutRequest? {
    try? LogoutRequest(serializedBytes: data)
  }
}
