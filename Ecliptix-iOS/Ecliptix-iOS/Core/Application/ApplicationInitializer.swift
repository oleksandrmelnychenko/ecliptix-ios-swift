// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

protocol ApplicationInitializing: AnyObject {

  func initialize(defaultCulture: String) async -> ApplicationInitializationResult
}

final class ApplicationInitializer {

  private static let lastInitErrorKey = "ecliptix_last_init_error"
  private static let lastInitStageKey = "ecliptix_last_init_stage"

  private let sessionBootstrap: SessionBootstrapService
  private let deviceRegistration: DeviceRegistrationService
  private let secureStorage: SecureStorageService
  private let localizationService: any LocalizationProviding
  private let pendingLogoutCoordinator: PendingLogoutCoordinator
  private let onNewInstance: () -> Void

  init(
    sessionBootstrap: SessionBootstrapService,
    deviceRegistration: DeviceRegistrationService,
    secureStorage: SecureStorageService,
    localizationService: any LocalizationProviding,
    pendingLogoutCoordinator: PendingLogoutCoordinator,
    onNewInstance: @escaping () -> Void
  ) {
    self.sessionBootstrap = sessionBootstrap
    self.deviceRegistration = deviceRegistration
    self.secureStorage = secureStorage
    self.localizationService = localizationService
    self.pendingLogoutCoordinator = pendingLogoutCoordinator
    self.onNewInstance = onNewInstance
  }

  func initialize(
    defaultCulture: String = "en-US"
  ) async -> ApplicationInitializationResult {
    AppLogger.app.info("Application init: started")
    recordStage("settings")

    let settingsResult = await secureStorage.initApplicationInstanceSettings(
      defaultCulture: defaultCulture
    )
    guard let (settings, isNewInstance) = settingsResult.ok() else {
      let details = settingsResult.err() ?? ""
      AppLogger.app.error(
        "Application init failed: settings init error: \(details, privacy: .public)")
      recordError(details)
      return .settingsInitializationFailed(details)
    }
    AppLogger.app.info(
      "Application init: settings loaded, isNewInstance=\(isNewInstance, privacy: .public), hasMembership=\((settings.membership != nil), privacy: .public), hasAccount=\((settings.currentAccountId != nil), privacy: .public)"
    )
    let culture = settings.culture.isEmpty ? "en-US" : settings.culture
    localizationService.setCulture(culture)

    let pendingLogoutConnectId = NetworkProvider.computeUniqueConnectId(
      deviceId: settings.deviceId,
      appInstanceId: settings.appInstanceId,
      exchangeType: .dataCenterEphemeralConnect
    )
    await pendingLogoutCoordinator.processPendingLogoutRequests(connectId: pendingLogoutConnectId)

    if isNewInstance {
      onNewInstance()
    }

    // --- Secrecy channel ---
    recordStage("secrecy")
    AppLogger.app.info("Application init: establishing secrecy channel")

    if !isNewInstance && BuildStampTracker.shouldInvalidatePersistedState() {
      BuildStampTracker.recordCurrentBuildStamp()
    }

    let connectIdResult = await sessionBootstrap.ensureSecrecyChannel(
      settings: settings,
      isNewInstance: isNewInstance
    )
    guard let connectId = connectIdResult.ok() else {
      let details = connectIdResult.err() ?? ""
      AppLogger.app.error(
        "Application init failed: secrecy channel error: \(details, privacy: .public)")
      recordError(details)
      return .secrecyChannelFailed(details)
    }

    // --- Device registration ---
    recordStage("device_registration")
    AppLogger.app.info("Application init: registering device")

    let registrationResult = await deviceRegistration.registerDevice(
      connectId: connectId,
      settings: settings
    )
    guard registrationResult.isOk else {
      let error = registrationResult.unwrapErr()
      AppLogger.app.error(
        "Application init failed: device registration error: \(error.logDescription, privacy: .public)"
      )
      recordError(error.logDescription)
      return .deviceRegistrationFailed(error.logDescription)
    }

    recordStage("completed")
    clearError()
    BuildStampTracker.recordCurrentBuildStamp()
    await pendingLogoutCoordinator.processPendingLogouts(connectId: connectId)
    AppLogger.app.info("Application init: completed")
    return .success
  }

  private func recordStage(_ stage: String) {
    UserDefaults.standard.set(stage, forKey: Self.lastInitStageKey)
  }

  private func recordError(_ details: String) {
    UserDefaults.standard.set(details, forKey: Self.lastInitErrorKey)
  }

  private func clearError() {
    UserDefaults.standard.set("", forKey: Self.lastInitErrorKey)
  }
}

extension ApplicationInitializer: ApplicationInitializing {}
