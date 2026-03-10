// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum ConnectIdResolver {

  static func resolve(
    settings: ApplicationInstanceSettings?,
    exchangeType: PubKeyExchangeType
  ) -> UInt32 {
    let deviceId = settings?.deviceId ?? NetworkConfiguration.default.deviceId
    let appInstanceId = settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    return NetworkProvider.computeUniqueConnectId(
      deviceId: deviceId,
      appInstanceId: appInstanceId,
      exchangeType: exchangeType
    )
  }

  static func current(
    exchangeType: PubKeyExchangeType,
    settingsProvider: () -> ApplicationInstanceSettings?
  ) -> UInt32 {
    resolve(settings: settingsProvider(), exchangeType: exchangeType)
  }
}
