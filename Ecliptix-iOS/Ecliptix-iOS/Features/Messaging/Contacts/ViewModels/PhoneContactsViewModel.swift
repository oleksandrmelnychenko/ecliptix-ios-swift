// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Contacts
import EcliptixProtos
import Foundation
import os.log

@Observable @MainActor
final class PhoneContactsViewModel: Resettable {

  var contacts: [PhoneContact] = [] {
    didSet { rebuildSections() }
  }

  var searchQuery: String = "" {
    didSet { rebuildSections() }
  }

  var isLoading: Bool = false
  var isPermissionDenied: Bool = false
  var matchedCount: Int = 0
  var contactToInvite: PhoneContact?

  private(set) var sections: [(letter: String, contacts: [PhoneContact])] = []

  var filteredContacts: [PhoneContact] {
    guard !searchQuery.isEmpty else { return contacts }
    let query = searchQuery.lowercased()
    return contacts.filter { contact in
      contact.fullName.lowercased().contains(query)
        || contact.phoneNumbers.contains { $0.contains(query) }
    }
  }

  private func rebuildSections() {
    let grouped = Dictionary(grouping: filteredContacts) { contact -> String in
      let first = contact.fullName.first.map { String($0).uppercased() } ?? "#"
      return first.first?.isLetter == true ? first : "#"
    }
    sections = grouped.sorted { $0.key < $1.key }.map { (letter: $0.key, contacts: $0.value) }
  }

  private let contactsService: PhoneContactsService
  private let profileService: ProfileRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private let onContactSelected: (Data) -> Void
  private var matchTask: Task<Void, Never>? {
    willSet { matchTask?.cancel() }
  }

  init(
    contactsService: PhoneContactsService,
    profileService: ProfileRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32,
    onContactSelected: @escaping (Data) -> Void = { _ in }
  ) {
    self.contactsService = contactsService
    self.profileService = profileService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
    self.onContactSelected = onContactSelected
  }

  func loadContacts() async {
    isLoading = true
    defer { isLoading = false }

    let status = contactsService.authorizationStatus
    if status == .denied || status == .restricted {
      isPermissionDenied = true
      return
    }

    if status == .notDetermined {
      let granted = await contactsService.requestAccess()
      if !granted {
        isPermissionDenied = true
        return
      }
    }

    isPermissionDenied = false

    do {
      let fetched = try await contactsService.fetchContacts()
      contacts = fetched
      AppLogger.app.info("PhoneContacts: fetched \(fetched.count, privacy: .public) contacts")
    } catch {
      AppLogger.app.error(
        "PhoneContacts: fetch failed, error=\(error.localizedDescription, privacy: .public)")
      contacts = []
    }

    matchTask = Task { await matchContacts() }
  }

  func selectContact(_ contact: PhoneContact) {
    guard let profile = contact.ecliptixProfile else { return }
    onContactSelected(profile.profileID)
  }

  func inviteContact(_ contact: PhoneContact) {
    contactToInvite = contact
  }

  func resetState() {
    matchTask?.cancel()
    matchTask = nil
    contacts = []
    searchQuery = ""
    isLoading = false
    isPermissionDenied = false
    matchedCount = 0
    contactToInvite = nil
  }

  private func matchContacts() async {
    guard let accountId = settingsProvider()?.currentAccountId else {
      AppLogger.app.warning("PhoneContacts: no accountId for matching")
      return
    }

    let batchSize = 5
    let delayMs: UInt64 = 100
    var matched = 0

    for i in stride(from: 0, to: contacts.count, by: batchSize) {
      guard !Task.isCancelled else { return }

      let batchEnd = min(i + batchSize, contacts.count)
      let batch = Array(contacts[i..<batchEnd])

      await withTaskGroup(of: (Int, AccountProfile?).self) { group in
        for (offset, contact) in batch.enumerated() {
          let index = i + offset
          let phone = contact.primaryPhone
          guard !phone.isEmpty else { continue }
          group.addTask { [profileService, connectIdProvider] in
            let connectId = connectIdProvider(.dataCenterEphemeralConnect)
            let result = await profileService.profileLookupByMobile(
              mobileNumber: phone,
              currentAccountId: accountId,
              connectId: connectId
            )
            return (index, result.ok() ?? nil)
          }
        }
        for await (index, profile) in group {
          guard !Task.isCancelled else { return }
          if let profile, index < contacts.count {
            contacts[index].ecliptixProfile = profile
            matched += 1
          }
        }
      }

      matchedCount = matched

      if batchEnd < contacts.count {
        try? await Task.sleep(for: .milliseconds(delayMs))
      }
    }

    contacts.sort { a, b in
      if a.isOnEcliptix != b.isOnEcliptix {
        return a.isOnEcliptix
      }
      return a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
    }

    AppLogger.app.info(
      "PhoneContacts: matching complete, matched=\(matched, privacy: .public) of \(self.contacts.count, privacy: .public)"
    )
  }
}
