// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os

@Observable @MainActor
final class AccountSettingsViewModel {

  var displayName: String = "" {
    didSet {
      validateDisplayName(displayName)
      updateInitials()
      scheduleSaveIfNeeded()
    }
  }

  var profileName: String = ""
  var mobileNumber: String = ""
  var profileInitials: String = "?"
  var isLoading: Bool = false
  var isSaving: Bool = false
  var showSavedConfirmation: Bool = false
  var displayNameError: String = ""
  var errorMessage: String = ""
  var hasError: Bool = false
  var hasDisplayNameError: Bool { !displayNameError.isEmpty }
  private let profileService: ProfileRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private var accountId: UUID?
  private var connectId: UInt32 = 0
  private var isInternalUpdate = false
  private var saveTask: Task<Void, Never>?
  private var confirmationDismissTask: Task<Void, Never>?
  private var isProfileLoaded = false

  init(
    profileService: ProfileRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.profileService = profileService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func cancelPendingTasks() {
    saveTask?.cancel()
    confirmationDismissTask?.cancel()
  }

  func loadProfile() async {
    guard !isProfileLoaded else { return }
    isLoading = true
    defer { isLoading = false }

    let settings = settingsProvider()
    guard let currentAccountId = settings?.currentAccountId else {
      AppLogger.ui.warning("AccountSettings: no current account ID")
      return
    }
    accountId = currentAccountId
    if let membership = settings?.membership {
      mobileNumber = membership.mobileNumber
    }
    connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await profileService.profileLookup(
      accountId: currentAccountId,
      connectId: connectId
    )
    switch result {
    case .ok(let profile):
      isInternalUpdate = true
      if let profile {
        profileName = profile.profileName
        displayName = profile.displayName
      }
      isInternalUpdate = false
      isProfileLoaded = true
    case .err(let error):
      AppLogger.ui.error("AccountSettings: profile lookup failed, error=\(error, privacy: .public)")
      errorMessage = String(localized: "Failed to load profile")
      hasError = true
    }
  }

  func saveDisplayName() async {
    guard let accountId, !profileName.isEmpty, !displayName.isEmpty,
      displayNameError.isEmpty
    else { return }
    isSaving = true
    defer { isSaving = false }

    let result = await profileService.profileUpsert(
      accountId: accountId,
      profileName: profileName,
      displayName: displayName,
      connectId: connectId
    )
    switch result {
    case .ok:
      showSavedConfirmation = true
      confirmationDismissTask?.cancel()
      confirmationDismissTask = Task {
        try? await Task.sleep(for: .seconds(1.5))
        guard !Task.isCancelled else { return }
        showSavedConfirmation = false
      }
    case .err(let error):
      AppLogger.ui.error("AccountSettings: profile upsert failed, error=\(error, privacy: .public)")
      errorMessage = String(localized: "Failed to save profile")
      hasError = true
    }
  }

  private func scheduleSaveIfNeeded() {
    guard !isInternalUpdate, isProfileLoaded, !displayName.isEmpty,
      displayNameError.isEmpty
    else { return }
    saveTask?.cancel()
    saveTask = Task {
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      await saveDisplayName()
    }
  }

  private func updateInitials() {
    let words = displayName.split(separator: " ").filter { !$0.isEmpty }
    if words.isEmpty {
      profileInitials = "?"
      return
    }
    if words.count == 1 {
      profileInitials = String(words[0].prefix(2)).uppercased()
    } else {
      let first = words[0].prefix(1)
      let last = words[words.count - 1].prefix(1)
      profileInitials = "\(first)\(last)".uppercased()
    }
  }

  private func validateDisplayName(_ name: String) {
    if name.isEmpty {
      displayNameError = ""
      return
    }
    guard name.count >= 2 else {
      displayNameError = String(localized: "Display name must be at least 2 characters")
      return
    }
    guard name.count <= 50 else {
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
}
