// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

final class DeviceRegistrationService {

  private let bootstrapClient: any ApplicationBootstrapClient

  private static let maxAttempts = AppConstants.Network.maxRetryAttempts
  private static let initialDelay: TimeInterval = 0.5
  private static let maxDelay: TimeInterval = 2.0

  init(bootstrapClient: any ApplicationBootstrapClient) {
    self.bootstrapClient = bootstrapClient
  }

  func registerDevice(
    connectId: UInt32,
    settings: ApplicationInstanceSettings
  ) async -> Result<Unit, RpcError> {
    var lastError: RpcError = .unexpected("Unknown device registration error")
    for attempt in 1...Self.maxAttempts {
      AppLogger.network.info(
        "Register device: attempt=\(attempt, privacy: .public), connectId=\(connectId, privacy: .public)"
      )
      let result = await bootstrapClient.registerDeviceRpc(
        connectId: connectId,
        settings: settings
      )
      if result.isOk {
        AppLogger.network.info("Register device: success connectId=\(connectId, privacy: .public)")
        return .ok(Unit.value)
      }

      let error = result.unwrapErr()
      lastError = error
      let shouldRetry = attempt < Self.maxAttempts && error.isRetryable
      if !shouldRetry {
        AppLogger.network.error(
          "Register device: final failure connectId=\(connectId, privacy: .public), attempt=\(attempt, privacy: .public), error=\(error.logDescription, privacy: .public)"
        )
        return .err(error)
      }
      AppLogger.network.warning(
        "Register device: retrying connectId=\(connectId, privacy: .public), attempt=\(attempt, privacy: .public), error=\(error.logDescription, privacy: .public)"
      )
      let delay = computeDelay(attempt: attempt)
      do {
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
      } catch {
        return .err(.unexpected("Device registration cancelled"))
      }
    }
    return .err(lastError)
  }

  private func computeDelay(attempt: Int) -> TimeInterval {
    let exponentialDelay = Self.initialDelay * pow(2.0, Double(attempt - 1))
    let capped = min(exponentialDelay, Self.maxDelay)
    let jitter = capped * Double.random(in: -0.25...0.25)
    return max(0.1, capped + jitter)
  }
}
