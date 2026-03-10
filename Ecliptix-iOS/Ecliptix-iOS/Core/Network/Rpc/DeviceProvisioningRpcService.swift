// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os.log

final class DeviceProvisioningRpcService {

  private let transport: EventGatewayTransport

  init(transport: EventGatewayTransport) {
    self.transport = transport
  }

  func registerDevice(
    device: Device,
    encryptedPayload: Data,
    cancellationToken: CancellationToken = .none
  ) async -> Result<Data, RpcError> {
    AppLogger.network.info(
      "DeviceRegistration: start deviceId=\(device.deviceId.uuidString, privacy: .public), appInstanceId=\(device.appInstanceId.uuidString, privacy: .public)"
    )
    _ = device
    _ = cancellationToken
    let protoEnvelope: ProtoSecureEnvelope
    do {
      protoEnvelope = try ProtoSecureEnvelope(serializedBytes: encryptedPayload)
    } catch {
      AppLogger.network.error(
        "DeviceRegistration: deserialize outbound failed, error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(
        .deserializationFailed(
          "outbound encrypted payload as SecureEnvelope: \(error.localizedDescription)"))
    }

    let result = await transport.unary(
      serviceType: .registerAppDevice,
      payload: protoEnvelope
    )
    switch result {
    case .ok(let response):
      let protoResponse: ProtoSecureEnvelope
      do {
        protoResponse = try ProtoSecureEnvelope(serializedBytes: response.payload)
      } catch {
        AppLogger.network.error(
          "DeviceRegistration: deserialize response failed, error=\(error.localizedDescription, privacy: .public)"
        )
        return .err(
          .deserializationFailed("SecureEnvelope response: \(error.localizedDescription)"))
      }

      let serializedEnvelope: Data
      do {
        serializedEnvelope = try protoResponse.serializedData()
      } catch {
        AppLogger.network.error(
          "DeviceRegistration: serialize response failed, error=\(error.localizedDescription, privacy: .public)"
        )
        return .err(.serializationFailed("SecureEnvelope response: \(error.localizedDescription)"))
      }
      AppLogger.network.info(
        "DeviceRegistration: success deviceId=\(device.deviceId.uuidString, privacy: .public)")
      return .ok(serializedEnvelope)
    case .err(let error):
      AppLogger.network.error(
        "DeviceRegistration: RPC failed deviceId=\(device.deviceId.uuidString, privacy: .public), error=\(error.logDescription, privacy: .public)"
      )
      return .err(error)
    }
  }
}

struct Device {

  let deviceId: UUID
  let appInstanceId: UUID
  let deviceType: DeviceType
  let platform: String
  let osVersion: String
  let appVersion: String

  init(
    deviceId: UUID,
    appInstanceId: UUID,
    deviceType: DeviceType = .mobile,
    platform: String = "iOS",
    osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
    appVersion: String = "1.0.0"
  ) {
    self.deviceId = deviceId
    self.appInstanceId = appInstanceId
    self.deviceType = deviceType
    self.platform = platform
    self.osVersion = osVersion
    self.appVersion = appVersion
  }
}

enum DeviceType: Int32 {
  case unknown = 0
  case mobile = 1
  case desktop = 2
  case tablet = 3
  case web = 4
}

struct DeviceRegistrationResponse {

  let result: RegistrationResult
  let message: String
  let deviceToken: Data?
  enum RegistrationResult {
    case success
    case alreadyRegistered
    case invalidRequest
    case internalError
  }
}
