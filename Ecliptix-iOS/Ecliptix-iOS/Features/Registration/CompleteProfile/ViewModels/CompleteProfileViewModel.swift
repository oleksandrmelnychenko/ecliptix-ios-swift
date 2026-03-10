// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

enum ProfileStep {
  case username
  case personalize
}

@Observable @MainActor
final class CompleteProfileViewModel: Resettable {

  var profileName: String = "" {
    didSet {
      if hasError { clearServerError() }
      validateProfileNameLocally(profileName)
      scheduleAvailabilityCheck()
    }
  }

  var displayName: String = "" {
    didSet {
      if hasError { clearServerError() }
      validateDisplayName(displayName)
    }
  }

  var profileNameError: String = ""
  var displayNameError: String = ""
  var isBusy: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var showImagePicker: Bool = false
  var selectedAvatarData: Data? = nil
  var isCheckingAvailability: Bool = false
  var profileNameAvailable: Bool? = nil
  var currentStep: ProfileStep = .username
  var userFacingError: String {
    guard hasError else { return "" }
    return ServerErrorMapper.userFacingMessage(errorMessage)
  }

  var hasProfileNameError: Bool { !profileNameError.isEmpty }
  var hasDisplayNameError: Bool { !displayNameError.isEmpty }
  var isCompletingProfile: Bool { isBusy }
  var profileNameValidationError: String { profileNameError }
  var displayNameValidationError: String { displayNameError }
  var isFormValid: Bool {
    switch currentStep {
    case .username: canProceedToPersonalize
    case .personalize: canComplete
    }
  }

  var isProfileNameAvailable: Bool { profileNameAvailable == true && profileNameError.isEmpty }
  var stepBadgeText: String {
    switch currentStep {
    case .username: String(localized: "Step 5 of 6")
    case .personalize: String(localized: "Step 6 of 6")
    }
  }

  var title: String {
    switch currentStep {
    case .username: String(localized: "Choose Your Username")
    case .personalize: String(localized: "Personalize Your Profile")
    }
  }

  var subtitle: String {
    switch currentStep {
    case .username: String(localized: "Your unique @handle on Ecliptix")
    case .personalize: String(localized: "Add a photo and display name")
    }
  }

  var buttonText: String {
    switch currentStep {
    case .username: String(localized: "Continue")
    case .personalize: String(localized: "Complete Registration")
    }
  }

  var showSkipButton: Bool { currentStep == .personalize }
  var canProceedToPersonalize: Bool {
    !isBusy && profileNameError.isEmpty
      && !profileName.isEmpty && profileNameAvailable == true
      && !isCheckingAvailability
  }

  var canComplete: Bool {
    !isBusy && displayNameError.isEmpty
      && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private let profileService: ProfileRpcService
  private let secureStorageService: SecureStorageService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private let onProfileCompleted: () -> Void
  private var availabilityCheckTask: Task<Void, Never>?
  private static let availabilityDebounceMs: UInt64 = 500
  private static let profileNameMinLength: Int = 3
  private static let profileNameMaxLength: Int = 30
  private static let displayNameMinLength: Int = 2
  private static let displayNameMaxLength: Int = 50
  private static let reservedNames: Set<String> = [
    "admin", "administrator", "root", "system", "ecliptix",
    "support", "help", "info", "null", "undefined",
    "moderator", "mod", "official", "bot", "service",
  ]

  init(
    profileService: ProfileRpcService,
    secureStorageService: SecureStorageService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    sessionId: String? = nil,
    mobileNumber: String? = nil,
    onProfileCompleted: @escaping () -> Void = {}
  ) {
    self.profileService = profileService
    self.secureStorageService = secureStorageService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
    self.onProfileCompleted = onProfileCompleted
  }

  func onAppear() {}

  func proceedToPersonalize() {
    guard canProceedToPersonalize else { return }
    currentStep = .personalize
  }

  func goBackToUsername() {
    guard currentStep == .personalize, !isBusy else { return }
    currentStep = .username
  }

  func completeProfile() async {
    guard canComplete else { return }
    isBusy = true
    defer { isBusy = false }

    let settings = settingsProvider()
    guard let accountId = settings?.currentAccountId else {
      AppLogger.auth.error("CompleteProfile: missing accountId in stored settings")
      errorMessage = String(localized: "Failed to save profile")
      hasError = true
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespaces)
    guard !trimmedDisplayName.isEmpty else {
      displayNameError = String(localized: "Display name is required")
      return
    }

    let result = await TransientErrorDetection.executeWithRetry {
      await profileService.profileUpsert(
        accountId: accountId,
        profileName: profileName,
        displayName: trimmedDisplayName,
        connectId: connectId
      )
    }
    guard result.isOk else {
      let rpcError = result.unwrapErr()
      AppLogger.auth.error(
        "CompleteProfile: profileUpsert failed, error=\(rpcError.logDescription, privacy: .public)")
      errorMessage = rpcError.userFacingMessage
      hasError = true
      return
    }
    guard await markRegistrationCompleted() else {
      return
    }
    AppLogger.auth.info(
      "CompleteProfile: profile saved for accountId=\(accountId.uuidString, privacy: .public), profileName=\(self.profileName, privacy: .public)"
    )
    onProfileCompleted()
  }

  func skipProfile() async {
    guard await markRegistrationCompleted() else {
      return
    }
    resetState()
    onProfileCompleted()
  }

  func clearServerError() {
    hasError = false
    errorMessage = ""
  }

  func resetState() {
    availabilityCheckTask?.cancel()
    availabilityCheckTask = nil
    currentStep = .username
    profileName = ""
    displayName = ""
    profileNameError = ""
    displayNameError = ""
    profileNameAvailable = nil
    isCheckingAvailability = false
    isBusy = false
  }

  private func scheduleAvailabilityCheck() {
    availabilityCheckTask?.cancel()
    profileNameAvailable = nil
    isCheckingAvailability = false
    guard !profileName.isEmpty, profileNameError.isEmpty else {
      return
    }

    let name = profileName
    isCheckingAvailability = true
    availabilityCheckTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(Self.availabilityDebounceMs))
      guard !Task.isCancelled else { return }
      guard let self, self.profileName == name else { return }
      let connectId = self.connectIdProvider(.dataCenterEphemeralConnect)
      let result = await self.profileService.profileNameAvailability(
        profileName: name,
        connectId: connectId
      )
      guard !Task.isCancelled, self.profileName == name else { return }
      self.isCheckingAvailability = false
      if let availability = result.ok() {
        self.profileNameAvailable = availability.isAvailable
        if !availability.isAvailable {
          self.profileNameError =
            availability.reason.isEmpty
            ? String(localized: "This profile name is already taken")
            : ServerErrorMapper.userFacingMessage(availability.reason)
        }
      } else {
        AppLogger.auth.warning(
          "CompleteProfile: profileNameAvailability check failed for '\(name, privacy: .public)', error=\(result.err()?.logDescription ?? "unknown", privacy: .public)"
        )
        self.profileNameAvailable = nil
      }
    }
  }

  private func validateProfileNameLocally(_ name: String) {
    profileNameAvailable = nil
    if name.isEmpty {
      profileNameError = ""
      return
    }
    guard name.count >= Self.profileNameMinLength else {
      profileNameError = String(localized: "Profile name must be at least 3 characters")
      return
    }
    guard name.count <= Self.profileNameMaxLength else {
      profileNameError = String(localized: "Profile name must be at most 30 characters")
      return
    }

    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      profileNameError = String(
        localized: "Profile name can only contain letters, numbers, and underscores")
      return
    }
    guard let first = name.first, first.isLetter || first.isNumber else {
      profileNameError = String(localized: "Profile name must start with a letter or number")
      return
    }
    guard !name.hasSuffix("_") else {
      profileNameError = String(localized: "Profile name must not end with an underscore")
      return
    }
    guard !name.contains("__") else {
      profileNameError = String(localized: "Profile name must not contain consecutive underscores")
      return
    }
    if Self.reservedNames.contains(name.lowercased()) {
      profileNameError = String(localized: "This profile name is reserved")
      return
    }
    profileNameError = ""
  }

  private func validateDisplayName(_ name: String) {
    if name.isEmpty {
      displayNameError = ""
      return
    }
    guard name.count >= Self.displayNameMinLength else {
      displayNameError = String(localized: "Display name must be at least 2 characters")
      return
    }
    guard name.count <= Self.displayNameMaxLength else {
      displayNameError = String(localized: "Display name must be at most 50 characters")
      return
    }

    let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(
      CharacterSet(charactersIn: "'-.,"))
    guard name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      displayNameError = String(localized: "Display name contains invalid characters")
      return
    }
    guard !name.hasPrefix(" ") && !name.hasSuffix(" ") else {
      displayNameError = String(localized: "Display name cannot start or end with spaces")
      return
    }
    if name.contains("  ") {
      displayNameError = String(localized: "Display name cannot have multiple consecutive spaces")
      return
    }
    displayNameError = ""
  }

  private func markRegistrationCompleted() async -> Bool {
    let checkpointResult = await secureStorageService.setRegistrationCheckpoint(.profileCompleted)
    guard checkpointResult.isOk else {
      let error = checkpointResult.err() ?? String(localized: "Failed to save profile")
      AppLogger.auth.error(
        "CompleteProfile: failed to persist completion checkpoint, error=\(error, privacy: .public)"
      )
      errorMessage = ServerErrorMapper.userFacingMessage(error)
      hasError = true
      return false
    }
    return true
  }
}
