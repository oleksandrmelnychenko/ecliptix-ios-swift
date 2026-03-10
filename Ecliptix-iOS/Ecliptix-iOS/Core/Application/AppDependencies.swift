// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

final class AppDependencies: AppCoordinatorDependencyProviding, @unchecked Sendable {

  static let shared: AppDependencies = AppDependencies()
  let networkProvider: NetworkProvider
  let appFlowResolver: AppFlowResolver
  let identityService: IdentityService
  let authenticationRpcService: AuthenticationRpcService
  let profileRpcService: ProfileRpcService
  let pinRpcService: PinRpcService
  let opaqueAuthenticationService: OpaqueAuthenticationService
  let opaqueRegistrationService: OpaqueRegistrationService
  let pinOpaqueService: PinOpaqueService
  let secureKeyRecoveryService: SecureKeyRecoveryService
  let secrecyChannelRpcService: SecrecyChannelRpcService
  let deviceProvisioningRpcService: DeviceProvisioningRpcService
  let applicationInitializer: any ApplicationInitializing
  let applicationStateManager: ApplicationStateManager
  let logoutService: LogoutService
  let messagingRpcService: MessagingRpcService
  let messagingEventService: MessagingEventService
  let phoneContactsService: PhoneContactsService
  let feedRpcService: FeedRpcService
  let accountScopedDatabaseProvider: AccountScopedDatabaseProvider
  let protocolStateStorage: ProtocolStateStorage
  let settings: DefaultSystemSettings
  private let pendingLogoutStorage: PendingLogoutStorage
  let secureStorageService: SecureStorageService

  private init() {
    networkProvider = .shared
    appFlowResolver = AppFlowResolver()
    identityService = .shared
    applicationStateManager = .shared
    protocolStateStorage = .shared
    secureStorageService = .shared
    pendingLogoutStorage = .shared
    settings = DefaultSystemSettings.load()
    accountScopedDatabaseProvider = .shared
    let localizationService = LocalizationService.shared
    let rpcServiceManager = RpcServiceManager.shared
    let ipGeolocationService = IpGeolocationService.shared
    let metadataProvider = DefaultMetadataProvider(
      deviceId: NetworkConfiguration.default.deviceId,
      appInstanceId: NetworkConfiguration.default.appInstanceId
    )
    var resolvedTransport: EventGatewayTransport?
    do {
      try rpcServiceManager.configure(
        networkConfiguration: .default,
        metadataProvider: metadataProvider
      )
      resolvedTransport = try rpcServiceManager.getTransport()
    } catch {
      AppLogger.app.error(
        "Failed to configure RpcServiceManager: \(error.localizedDescription, privacy: .public)")
    }

    let transport =
      resolvedTransport
      ?? EventGatewayTransport(
        channelProvider: GrpcChannelProvider(configuration: .default),
        metadataProvider: metadataProvider
      )
    let connectIdProvider: (PubKeyExchangeType) -> UInt32 = { [secureStorageService] exchangeType in
      ConnectIdResolver.resolve(
        settings: secureStorageService.settings,
        exchangeType: exchangeType
      )
    }
    authenticationRpcService = AuthenticationRpcService(
      transport: transport,
      secureSessionClient: networkProvider,
      connectIdProvider: connectIdProvider,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
    profileRpcService = ProfileRpcService(
      transport: transport,
      secureSessionClient: networkProvider,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
    pinRpcService = PinRpcService(
      transport: transport,
      secureSessionClient: networkProvider,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
    opaqueAuthenticationService = OpaqueAuthenticationService(
      secureSessionClient: networkProvider,
      authenticationRpcService: authenticationRpcService,
      identityService: identityService,
      secureStorageService: secureStorageService
    )
    opaqueRegistrationService = OpaqueRegistrationService(
      secureSessionClient: networkProvider,
      authenticationRpcService: authenticationRpcService,
      secureStorageService: secureStorageService
    )
    pinOpaqueService = PinOpaqueService(
      secureSessionClient: networkProvider,
      pinRpcService: pinRpcService,
      secureStorageService: secureStorageService
    )
    secureKeyRecoveryService = SecureKeyRecoveryService(
      secureSessionClient: networkProvider,
      authenticationRpcService: authenticationRpcService,
      secureStorageService: secureStorageService
    )
    secrecyChannelRpcService = SecrecyChannelRpcService(transport: transport)
    deviceProvisioningRpcService = DeviceProvisioningRpcService(transport: transport)
    messagingRpcService = MessagingRpcService(
      transport: transport,
      secureSessionClient: networkProvider,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
    messagingEventService = MessagingEventService(
      streamRequestExecutor: networkProvider,
      connectIdProvider: connectIdProvider
    )
    feedRpcService = FeedRpcService(
      transport: transport,
      secureSessionClient: networkProvider,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
    phoneContactsService = PhoneContactsService()
    let sessionBootstrap = SessionBootstrapService(
      bootstrapClient: networkProvider,
      secureStorage: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService,
      stateManager: applicationStateManager
    )
    let deviceRegistration = DeviceRegistrationService(
      bootstrapClient: networkProvider
    )
    let pendingLogoutCoordinator = PendingLogoutCoordinator(
      secureStorage: secureStorageService,
      sessionBootstrap: sessionBootstrap,
      pendingLogoutStorage: pendingLogoutStorage,
      pendingLogoutTransportProvider: rpcServiceManager
    )
    let capturedNetworkProvider = networkProvider
    let capturedIpGeolocation = ipGeolocationService
    applicationInitializer = ApplicationInitializer(
      sessionBootstrap: sessionBootstrap,
      deviceRegistration: deviceRegistration,
      secureStorage: secureStorageService,
      localizationService: localizationService,
      pendingLogoutCoordinator: pendingLogoutCoordinator,
      onNewInstance: {
        AppDependencies.fetchIpGeolocationInBackground(
          ipGeolocationService: capturedIpGeolocation,
          bootstrapClient: capturedNetworkProvider
        )
      }
    )
    let pendingProcessor = PendingLogoutProcessor(
      pendingStorage: pendingLogoutStorage,
      transport: transport
    )
    let logoutProofHandler = LogoutProofHandler(
      identityService: identityService,
      secureStorage: secureStorageService
    )
    logoutService = LogoutService(
      authService: authenticationRpcService,
      identityService: identityService,
      secureStorage: secureStorageService,
      stateManager: applicationStateManager,
      proofHandler: logoutProofHandler,
      pendingStorage: pendingLogoutStorage,
      secureSessionClient: networkProvider,
      pendingProcessor: pendingProcessor,
      pendingLogoutTransportProvider: rpcServiceManager
    )
  }

  func resolveStoredIdentity() -> (accountId: UUID, membershipId: UUID)? {
    guard
      let settings = secureStorageService.settings,
      let accountId = settings.currentAccountId,
      let membershipId = settings.membership?.membershipId
    else {
      return nil
    }
    return (accountId, membershipId)
  }

  func activateAccountDatabase(accountId: UUID) -> Bool {
    let masterKeyResult = identityService.loadMasterKeySync(forAccountId: accountId)
    guard case .ok(let masterKey) = masterKeyResult else {
      AppLogger.app.warning(
        "No stored master key material for accountId=\(accountId.uuidString, privacy: .public), skipping DB activation"
      )
      return false
    }

    let dbEncryptionKey = IdentityService.deriveRootKey(from: masterKey, accountId: accountId)
    do {
      try accountScopedDatabaseProvider.activate(
        accountId: accountId, encryptionKey: dbEncryptionKey)
      return true
    } catch {
      AppLogger.app.error(
        "Failed to activate account database: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  func deactivateAccountDatabase() {
    accountScopedDatabaseProvider.deactivate()
  }

  private var realtimeTask: Task<Void, Never>?

  func startRealtimeServices() {
    realtimeTask?.cancel()
    realtimeTask = Task { [weak self] in
      await self?.messagingEventService.start()
    }
  }

  func stopRealtimeServices() async {
    realtimeTask?.cancel()
    realtimeTask = nil
    await messagingEventService.stop()
  }

  func currentAppSettings() -> ApplicationInstanceSettings? {
    secureStorageService.settings
  }

  func currentConnectId(exchangeType: PubKeyExchangeType = .dataCenterEphemeralConnect) -> UInt32 {
    ConnectIdResolver.resolve(
      settings: secureStorageService.settings,
      exchangeType: exchangeType
    )
  }

  func weakSettingsProvider() -> () -> ApplicationInstanceSettings? {
    { [weak self] in self?.secureStorageService.settings }
  }

  func weakConnectIdProvider() -> (PubKeyExchangeType) -> UInt32 {
    { [weak self] exchangeType in
      guard let self else { return 0 }
      return ConnectIdResolver.resolve(
        settings: self.secureStorageService.settings,
        exchangeType: exchangeType
      )
    }
  }

  private static func fetchIpGeolocationInBackground(
    ipGeolocationService: any IpGeolocating,
    bootstrapClient: any ApplicationBootstrapClient
  ) {
    Task(priority: .utility) {
      let result = await ipGeolocationService.getIpCountry()
      guard let ipCountry = result.ok() else {
        AppLogger.network.warning("IP geolocation failed: \(result.err() ?? "", privacy: .public)")
        return
      }
      AppLogger.network.info("IP geolocation: country=\(ipCountry.country, privacy: .public)")
      bootstrapClient.setCountry(ipCountry.country)
    }
  }

  func shutdown() async {
    realtimeTask?.cancel()
    realtimeTask = nil
    await networkProvider.dispose()
  }
}

struct DefaultSystemSettings {

  let defaultTheme: String
  let environment: String
  let culture: String
  let privacyPolicyURL: String
  let termsOfServiceURL: String
  let supportURL: String

  static func load() -> DefaultSystemSettings {
    DefaultSystemSettings(
      defaultTheme: AppConstants.SystemSettings.defaultTheme,
      environment: AppConstants.SystemSettings.environment,
      culture: Locale.current.identifier,
      privacyPolicyURL: AppConstants.SystemSettings.privacyPolicyURL,
      termsOfServiceURL: AppConstants.SystemSettings.termsOfServiceURL,
      supportURL: AppConstants.SystemSettings.supportURL
    )
  }
}
