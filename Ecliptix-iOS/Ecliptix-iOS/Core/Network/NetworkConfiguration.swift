// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct NetworkConfiguration: Codable, Sendable {

  let baseURL: String
  let port: Int
  let useTLS: Bool
  let requestTimeout: TimeInterval
  let connectionTimeout: TimeInterval
  let maxRetryAttempts: Int
  let retryDelay: TimeInterval
  let deviceId: UUID
  let appInstanceId: UUID
  let platform: String
  let culture: String
  static let `default`: NetworkConfiguration = {
    #if DEBUG
      let debug = resolveDebugEndpoint()
      return NetworkConfiguration(
        baseURL: debug.host,
        port: debug.port,
        useTLS: debug.useTLS,
        requestTimeout: AppConstants.Network.requestTimeout,
        connectionTimeout: AppConstants.Network.connectionTimeout,
        maxRetryAttempts: AppConstants.Network.maxRetryAttempts,
        retryDelay: AppConstants.Network.retryDelay,
        deviceId: DeviceInfo.deviceId,
        appInstanceId: DeviceInfo.appInstanceId,
        platform: DeviceInfo.platform,
        culture: Locale.current.identifier
      )
    #else
      return NetworkConfiguration(
        baseURL: AppConstants.Network.productionHost,
        port: AppConstants.Network.tlsPort,
        useTLS: true,
        requestTimeout: AppConstants.Network.requestTimeout,
        connectionTimeout: AppConstants.Network.connectionTimeout,
        maxRetryAttempts: AppConstants.Network.maxRetryAttempts,
        retryDelay: AppConstants.Network.retryDelay,
        deviceId: DeviceInfo.deviceId,
        appInstanceId: DeviceInfo.appInstanceId,
        platform: DeviceInfo.platform,
        culture: Locale.current.identifier
      )
    #endif
  }()
  static let development: NetworkConfiguration = NetworkConfiguration(
    baseURL: AppConstants.Network.developmentHost,
    port: AppConstants.Network.tlsPort,
    useTLS: true,
    requestTimeout: AppConstants.Network.developmentRequestTimeout,
    connectionTimeout: AppConstants.Network.developmentConnectionTimeout,
    maxRetryAttempts: AppConstants.Network.developmentMaxRetryAttempts,
    retryDelay: AppConstants.Network.developmentRetryDelay,
    deviceId: DeviceInfo.deviceId,
    appInstanceId: DeviceInfo.appInstanceId,
    platform: DeviceInfo.platform,
    culture: Locale.current.identifier
  )
  #if DEBUG

    private static func resolveDebugEndpoint() -> (host: String, port: Int, useTLS: Bool) {
      let env = ProcessInfo.processInfo.environment
      let defaults = UserDefaults.standard
      #if targetEnvironment(simulator)
        let fallbackHost = AppConstants.Network.developmentHost
        let fallbackPort = AppConstants.Network.tlsPort
        let fallbackTLS = true
      #else
        let fallbackHost = AppConstants.Network.deviceDebugHost
        let fallbackPort = AppConstants.Network.localPort
        let fallbackTLS = false
      #endif
      let rawHost =
        env[AppConstants.EnvironmentKey.apiHost]
        ?? defaults.string(forKey: AppConstants.DefaultsKey.apiHost)
      let trimmedHost = rawHost?.trimmingCharacters(in: .whitespacesAndNewlines)
      let host: String
      if let trimmedHost, !trimmedHost.isEmpty {
        host = trimmedHost
      } else {
        host = fallbackHost
      }

      let port =
        Int(env[AppConstants.EnvironmentKey.apiPort] ?? "")
        ?? defaults.integer(forKey: AppConstants.DefaultsKey.apiPort)
      let resolvedPort = port > 0 ? port : fallbackPort
      let tlsSource =
        env[AppConstants.EnvironmentKey.apiTLS]
        ?? defaults.string(forKey: AppConstants.DefaultsKey.apiTLS)
      let resolvedTLS: Bool
      if let tlsSource {
        resolvedTLS = ["1", "true", "yes"].contains(tlsSource.lowercased())
      } else {
        resolvedTLS = fallbackTLS
      }
      return (host, resolvedPort, resolvedTLS)
    }
  #endif
}

private struct DeviceInfo {

  static let deviceId: UUID = resolveOrCreateId(keychainKey: "ecliptix_device_id")
  static let appInstanceId: UUID = resolveOrCreateId(keychainKey: "ecliptix_app_instance_id")
  static let platform: String = {
    #if os(iOS)
      return AppConstants.Platform.iOS
    #elseif os(macOS)
      return AppConstants.Platform.macOS
    #else
      return AppConstants.Platform.unknown
    #endif
  }()

  private static func resolveOrCreateId(keychainKey: String) -> UUID {
    if let existing = keychainLoad(key: keychainKey) {
      return existing
    }

    let newId = UUID()
    keychainStore(key: keychainKey, value: newId)
    return newId
  }

  private static func keychainLoad(key: String) -> UUID? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ecliptix.device-info",
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data,
      let str = String(data: data, encoding: .utf8),
      let uuid = UUID(uuidString: str)
    else { return nil }
    return uuid
  }

  private static func keychainStore(key: String, value: UUID) {
    let data = Data(value.uuidString.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.ecliptix.device-info",
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    SecItemDelete(query as CFDictionary)
    SecItemAdd(query as CFDictionary, nil)
  }
}
