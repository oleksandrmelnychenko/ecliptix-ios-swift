// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct NetworkProviderDependencies {

  let configuration: NetworkConfiguration
  let metadataProvider: MetadataProvider
  let secureStorage: SecureStorageProvider
  let stateStorage: NetworkProtocolStateStorage

  init(
    configuration: NetworkConfiguration = .default,
    metadataProvider: MetadataProvider,
    secureStorage: SecureStorageProvider,
    stateStorage: NetworkProtocolStateStorage
  ) {
    self.configuration = configuration
    self.metadataProvider = metadataProvider
    self.secureStorage = secureStorage
    self.stateStorage = stateStorage
  }
}

protocol MetadataProvider {

  var deviceId: UUID { get }
  var appInstanceId: UUID { get }
  var platform: String { get }
  var culture: String { get }
  var appVersion: String { get }
  var osVersion: String { get }
}

final class DefaultMetadataProvider: MetadataProvider {

  let deviceId: UUID
  let appInstanceId: UUID
  let platform: String
  var culture: String {
    Locale.current.language.languageCode?.identifier ?? Locale.current.identifier
  }
  let appVersion: String
  let osVersion: String

  init(
    deviceId: UUID,
    appInstanceId: UUID,
    platform: String = "iOS",
    appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
      ?? "1.0.0",
    osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString
  ) {
    self.deviceId = deviceId
    self.appInstanceId = appInstanceId
    self.platform = platform
    self.appVersion = appVersion
    self.osVersion = osVersion
  }
}

protocol SecureStorageProvider {

  func store(key: String, data: Data) async throws

  func retrieve(key: String) async throws -> Data?

  func delete(key: String) async throws

  func exists(key: String) async -> Bool
}

protocol NetworkProtocolStateStorage {

  func saveSessionState(_ state: SessionState, for connectId: UInt32) async -> Result<
    Unit, NetworkFailure
  >

  func loadSessionState(for connectId: UInt32) async -> Result<SessionState?, NetworkFailure>

  func deleteSessionState(for connectId: UInt32) async -> Result<Unit, NetworkFailure>

  func listSessionStates() async -> Result<[SessionState], NetworkFailure>

  func deleteAllSessionStates() async -> Result<Unit, NetworkFailure>
}

struct SessionState: Codable {

  let connectId: UInt32
  let exchangeType: PubKeyExchangeType
  let peerHandshakeInit: Data
  let membershipId: Data
  let accountId: Data
  let identitySeed: Data?
  let nativeState: Data?
  let createdAt: Date
  private enum CodingKeys: String, CodingKey {
    case connectId, exchangeType, peerHandshakeInit
    case membershipId, accountId, nativeState, createdAt
  }

  init(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType,
    peerHandshakeInit: Data,
    membershipId: Data = Data(),
    accountId: Data = Data(),
    identitySeed: Data? = nil,
    nativeState: Data? = nil,
    createdAt: Date = Date()
  ) {
    self.connectId = connectId
    self.exchangeType = exchangeType
    self.peerHandshakeInit = peerHandshakeInit
    self.membershipId = membershipId
    self.accountId = accountId
    self.identitySeed = identitySeed
    self.nativeState = nativeState
    self.createdAt = createdAt
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    connectId = try container.decode(UInt32.self, forKey: .connectId)
    exchangeType = try container.decode(PubKeyExchangeType.self, forKey: .exchangeType)
    peerHandshakeInit = try container.decode(Data.self, forKey: .peerHandshakeInit)
    membershipId = try container.decode(Data.self, forKey: .membershipId)
    accountId = try container.decode(Data.self, forKey: .accountId)
    identitySeed = nil
    nativeState = try container.decodeIfPresent(Data.self, forKey: .nativeState)
    createdAt = try container.decode(Date.self, forKey: .createdAt)
  }
}

enum PubKeyExchangeType: Int, Codable {
  case initialHandshake = 0
  case dataCenterEphemeralConnect = 1
  case serverStreaming = 2
  case deviceToDevice = 3
}
