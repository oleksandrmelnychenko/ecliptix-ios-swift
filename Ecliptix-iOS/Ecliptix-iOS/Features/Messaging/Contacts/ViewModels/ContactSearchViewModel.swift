import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class ContactSearchViewModel: Resettable {

  var contacts: [MemberDisplayItem] = []
  var searchQuery: String = "" {
    didSet { debouncedSearch() }
  }

  var isSearching = false

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32
  private var searchTask: Task<Void, Never>?

  init(
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func resetState() {
    searchTask?.cancel()
    contacts = []
    searchQuery = ""
    isSearching = false
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  private func debouncedSearch() {
    searchTask?.cancel()

    guard !searchQuery.isEmpty else {
      contacts = []
      return
    }

    searchTask = Task {
      try? await Task.sleep(for: .milliseconds(300))
      guard !Task.isCancelled else { return }
      await performSearch()
    }
  }

  private func performSearch() async {
    guard let currentAccountId else {
      AppLogger.messaging.error("ContactSearch: missing accountId for search")
      contacts = []
      return
    }
    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.warning("ContactSearch: no membershipId for search")
      contacts = []
      return
    }

    isSearching = true
    defer { isSearching = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.searchContacts(
      accountId: currentAccountId,
      membershipId: membershipId.protobufBytes,
      query: searchQuery,
      pageSize: 30,
      connectId: connectId
    )
    guard !Task.isCancelled else { return }
    switch result {
    case .ok(let response):
      contacts = response.contacts.map { c in
        MemberDisplayItem(
          id: c.membershipID,
          accountId: c.accountID,
          displayName: c.displayName,
          profileName: c.profileName,
          avatarUrl: c.hasAvatarURL ? c.avatarURL : nil,
          role: .member,
          joinedAt: nil
        )
      }
    case .err(let error):
      AppLogger.messaging.warning("ContactSearch: search failed: \(error, privacy: .public)")
      contacts = []
    }
  }
}
