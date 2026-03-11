import CryptoKit
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import Security
import os.log

extension NetworkProvider {

  static let shared: NetworkProvider = {
    let secureStorage = KeychainStorage()
    let metadataProvider = DefaultMetadataProvider(
      deviceId: NetworkConfiguration.default.deviceId,
      appInstanceId: NetworkConfiguration.default.appInstanceId
    )
    let retryPolicyProvider = DefaultRetryPolicyProvider()
    let connectivityService = ReachabilityService()
    let services = NetworkProviderServices(
      connectivityService: connectivityService,
      retryStrategy: ExponentialBackoffStrategy(retryPolicyProvider: retryPolicyProvider),
      pendingRequestManager: InMemoryPendingRequestManager()
    )
    let stateEncryptionKey = requiredSessionStateEncryptionKey(using: secureStorage)

    let dependencies = NetworkProviderDependencies(
      metadataProvider: metadataProvider,
      secureStorage: secureStorage,
      stateStorage: FileSystemStateStorage(
        encryptionKey: stateEncryptionKey
      )
    )
    let security = NetworkProviderSecurity(
      retryPolicyProvider: retryPolicyProvider,
      platformSecurityProvider: DefaultPlatformSecurityProvider(secureStorage: secureStorage)
    )
    let provider = NetworkProvider(
      dependencies: dependencies,
      services: services,
      security: security,
      rpcServiceManager: .shared,
      secureStorageService: .shared,
      protocolStateStorage: .shared,
      runtime: NetworkProviderRuntime()
    )
    let observer = ConnectivityObserver(
      connectivityService: connectivityService,
      networkProvider: provider
    )
    observer.start()
    _connectivityObserver = observer
    return provider
  }()
  private static var _connectivityObserver: ConnectivityObserver?

  private static func requiredSessionStateEncryptionKey(
    using secureStorage: SecureStorageProvider
  ) -> Data {
    do {
      return try DefaultPlatformSecurityProvider(secureStorage: secureStorage)
        .getOrCreateSessionStateKeySync()
    } catch {
      let message =
        "Session state key initialization failed: \(error.localizedDescription). Refusing to continue with an ephemeral fallback."
      AppLogger.security.fault("\(message, privacy: .public)")
      fatalError(message)
    }
  }

  static func computeUniqueConnectId(
    deviceId: UUID,
    appInstanceId: UUID,
    exchangeType: PubKeyExchangeType
  ) -> UInt32 {
    let appInstanceBytes: [UInt8] = dotNetGuidBytes(appInstanceId)
    let deviceBytes: [UInt8] = dotNetGuidBytes(deviceId)
    let contextType = UInt32(exchangeType.rawValue).bigEndian
    var material: Data = Data()
    material.append(contentsOf: appInstanceBytes)
    material.append(contentsOf: deviceBytes)
    withUnsafeBytes(of: contextType) { material.append(contentsOf: $0) }
    let digest: SHA256.Digest = SHA256.hash(data: material)
    let prefix: [PrefixSequence<SHA256.Digest>.Element] = Array(
      digest.prefix(AppConstants.Crypto.requestKeyHashPrefixBytes))
    return (UInt32(prefix[0]) << 24)
      | (UInt32(prefix[1]) << 16)
      | (UInt32(prefix[2]) << 8)
      | UInt32(prefix[3])
  }

  func resolveConnectIdForActiveSession(preferredConnectId: UInt32) -> UInt32 {
    let preferredResult = nativeSessions.get(connectId: preferredConnectId)
    if preferredResult.isOk {
      return preferredConnectId
    }
    if let activeConnectId = nativeSessions.singleActiveConnectId() {
      AppLogger.network.info(
        "Fallback to active session connectId=\(activeConnectId), preferred=\(preferredConnectId)")
      return activeConnectId
    }
    return preferredConnectId
  }

  func clearConnection(connectId: UInt32) {
    nativeSessions.remove(connectId: connectId)
  }

  func restoreSecrecyChannel(
    sealedState: Data,
    connectId: UInt32,
    settings: ApplicationInstanceSettings,
    sealKey: Data,
    minExternalCounter: UInt64
  ) async -> Result<Unit, String> {
    do {
      let (session, _) = try NativeProtocolSession.restore(
        sealedState: sealedState,
        key: sealKey,
        minExternalCounter: minExternalCounter
      )
      nativeSessions.store(connectId: connectId, session: session)
      return .ok(.value)
    } catch let error as ProtocolError {
      return .err(error.message)
    } catch {
      return .err(error.localizedDescription)
    }
  }

  func establishSecrecyChannel(
    connectId: UInt32,
    exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect
  ) async -> Result<Unit, String> {
    let result = await establishSecrecyChannel(
      request: SecrecyChannelRequest(
        connectId: connectId,
        exchangeType: exchangeType
      )
    )
    if result.isOk {
      return .ok(.value)
    }
    return .err(result.err()?.message ?? "")
  }

  func ensureProtocolForStreaming() async -> Result<UInt32, String> {
    let settings = secureStorageService.settings
    let deviceId = settings?.deviceId ?? NetworkConfiguration.default.deviceId
    let appInstanceId = settings?.appInstanceId ?? NetworkConfiguration.default.appInstanceId
    let streamConnectId = Self.computeUniqueConnectId(
      deviceId: deviceId,
      appInstanceId: appInstanceId,
      exchangeType: .serverStreaming
    )
    if nativeSessions.get(connectId: streamConnectId).isOk {
      return .ok(streamConnectId)
    }
    initiateProtocol(deviceId: deviceId, appInstanceId: appInstanceId, connectId: streamConnectId)
    let result = await establishSecrecyChannel(
      request: SecrecyChannelRequest(
        connectId: streamConnectId,
        exchangeType: .serverStreaming
      )
    )
    guard result.isOk else {
      return .err(result.err()?.message ?? "")
    }
    return .ok(streamConnectId)
  }

  func persistSessionState(
    connectId: UInt32,
    accountId: Data,
    sealKey: Data,
    externalCounter: UInt64
  ) async -> Result<Unit, String> {
    let sessionResult = nativeSessions.get(connectId: connectId)
    guard case .ok(let session) = sessionResult else {
      return .err("No active session for connectId \(connectId)")
    }
    guard secureStorageService.settings != nil else {
      return .err("Application settings not initialized")
    }
    do {
      let sealedState = try session.exportSealedState(
        key: sealKey, externalCounter: externalCounter)
      return await protocolStateStorage.saveState(
        sealedState,
        externalCounter: externalCounter,
        connectId: String(connectId),
        accountId: accountId
      )
    } catch let error as ProtocolError {
      return .err(error.message)
    } catch {
      return .err(error.localizedDescription)
    }
  }

  @discardableResult
  func initiateProtocol(
    deviceId: UUID,
    appInstanceId: UUID,
    connectId: UInt32
  ) -> Bool {
    runtime.instanceSettingsStore.set(
      NetworkProviderInstanceSettings(
        deviceId: deviceId,
        appInstanceId: appInstanceId,
        culture: Locale.current.identifier
      )
    )
    clearConnection(connectId: connectId)
    let initResult = EPPNative.initialize()
    guard initResult == EPPNative.EppErrorCode.success.rawValue else {
      AppLogger.security.error("Failed to initialize native protocol library, code: \(initResult)")
      return false
    }
    do {
      let identity = try EcliptixIdentityKeys()
      nativeSessions.storeIdentity(connectId: connectId, identity: identity)
      return true
    } catch {
      AppLogger.security.error(
        "Failed to create native identity for connectId \(connectId): \(error)")
      return false
    }
  }

  func recreateProtocolWithMasterKey(
    masterKey: Data,
    membershipId: UUID,
    accountId: UUID,
    connectId: UInt32
  ) async -> Result<Unit, String> {
    _ = accountId
    guard masterKey.count == EPPConstants.SEED_LENGTH else {
      return .err("Master key must be \(EPPConstants.SEED_LENGTH) bytes")
    }
    do {
      let identity = try EcliptixIdentityKeys(
        seed: masterKey,
        membershipId: membershipId.uuidString
      )
      nativeSessions.storeIdentity(connectId: connectId, identity: identity)
      return .ok(Unit.value)
    } catch let error as ProtocolError {
      return .err("Failed to recreate protocol identity: \(error.message)")
    } catch {
      return .err("Failed to recreate protocol identity: \(error.localizedDescription)")
    }
  }

  func getServerPublicKey(connectId: UInt32) async -> Result<Data, NetworkFailure> {
    let keyResult = nativeSessions.getServerPublicKey(connectId: connectId)
    guard let serverKey = keyResult.ok() else {
      return .err(.protocolStateMismatch("Server public key not found for connectId \(connectId)"))
    }
    return .ok(serverKey)
  }
}

private func dotNetGuidBytes(_ uuid: UUID) -> [UInt8] {
  var bytes = Array(uuid.protobufBytes)
  bytes.swapAt(0, 3)
  bytes.swapAt(1, 2)
  bytes.swapAt(4, 5)
  bytes.swapAt(6, 7)
  return bytes
}
