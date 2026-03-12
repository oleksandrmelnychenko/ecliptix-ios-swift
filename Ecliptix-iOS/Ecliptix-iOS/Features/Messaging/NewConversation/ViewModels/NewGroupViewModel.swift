import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class NewGroupViewModel: Resettable {

  var contacts: [MemberDisplayItem] = []
  var filteredContacts: [MemberDisplayItem] = []
  var selectedMemberIds: Set<Data> = []
  var searchQuery: String = "" { didSet { filterContacts() } }
  var isLoading: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""

  private let messagingService: MessagingRpcService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> ConnectId
  private var allContacts: [MemberDisplayItem] = []

  init(
    messagingService: MessagingRpcService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> ConnectId
  ) {
    self.messagingService = messagingService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  var selectedMembers: [MemberDisplayItem] {
    allContacts.filter { selectedMemberIds.contains($0.id) }
  }

  var canContinue: Bool {
    !selectedMemberIds.isEmpty
  }

  func loadContacts() async {
    isLoading = true
    defer { isLoading = false }

    hasError = false
    errorMessage = ""

    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("NewGroup: missing membershipId, cannot load contacts")
      applyContactsLoadFailure(String(localized: "Missing membership identity"))
      return
    }
    guard let currentAccountId else {
      AppLogger.messaging.error("NewGroup: no accountId, cannot load contacts")
      applyContactsLoadFailure(String(localized: "Missing account information"))
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let membershipIdBytes = membershipId.protobufBytes
    var accumulated: [MemberDisplayItem] = []
    var pageToken = ""

    while true {
      let result = await messagingService.listContacts(
        accountId: currentAccountId,
        membershipId: membershipIdBytes,
        pageSize: 100,
        pageToken: pageToken,
        connectId: connectId
      )
      switch result {
      case .ok(let response):
        accumulated.append(contentsOf: response.contacts.map { c in
          MemberDisplayItem(
            id: c.membershipID,
            accountId: c.accountID,
            displayName: c.displayName,
            handle: c.handle,
            avatarUrl: c.hasAvatarURL ? c.avatarURL : nil,
            role: .member,
            joinedAt: nil
          )
        })
        if response.nextPageToken.isEmpty {
          allContacts = accumulated
          contacts = allContacts
          filteredContacts = allContacts
          hasError = false
          errorMessage = ""
          return
        }
        pageToken = response.nextPageToken
      case .err(let error):
        AppLogger.messaging.error(
          "NewGroup: failed to load contacts: \(error.logDescription, privacy: .public)")
        if accumulated.isEmpty {
          applyContactsLoadFailure(error.userFacingMessage)
        } else {
          allContacts = accumulated
          contacts = allContacts
          filteredContacts = allContacts
        }
        return
      }
    }
  }

  func toggleMember(_ id: Data) {
    if selectedMemberIds.contains(id) {
      selectedMemberIds.remove(id)
    } else {
      selectedMemberIds.insert(id)
    }
  }

  func resetState() {
    allContacts = []
    contacts = []
    filteredContacts = []
    selectedMemberIds = []
    searchQuery = ""
    isLoading = false
    hasError = false
    errorMessage = ""
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  private func filterContacts() {
    if searchQuery.isEmpty {
      filteredContacts = allContacts
    } else {
      let q = searchQuery.lowercased()
      filteredContacts = allContacts.filter {
        $0.displayName.lowercased().contains(q) || $0.handle.lowercased().contains(q)
      }
    }
  }

  private func applyContactsLoadFailure(_ message: String) {
    #if DEBUG
      loadMockContacts()
      contacts = allContacts
      filteredContacts = allContacts
      hasError = true
      errorMessage = message
    #else
      allContacts = []
      contacts = []
      filteredContacts = []
      hasError = true
      errorMessage = message
    #endif
  }

  private func loadMockContacts() {
    allContacts = [
      MemberDisplayItem(
        id: Data([1]), accountId: Data([1]), displayName: "Alice Johnson", handle: "alice",
        avatarUrl: nil, role: .member, joinedAt: nil),
      MemberDisplayItem(
        id: Data([2]), accountId: Data([2]), displayName: "Bob Smith", handle: "bob",
        avatarUrl: nil, role: .member, joinedAt: nil),
      MemberDisplayItem(
        id: Data([3]), accountId: Data([3]), displayName: "Carol Williams", handle: "carol",
        avatarUrl: nil, role: .member, joinedAt: nil),
      MemberDisplayItem(
        id: Data([4]), accountId: Data([4]), displayName: "David Brown", handle: "david",
        avatarUrl: nil, role: .member, joinedAt: nil),
    ]
  }
}
