import EcliptixProtos
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

@Observable @MainActor
final class NewConversationViewModel: Resettable {

  var contacts: [MemberDisplayItem] = []
  var searchQuery: String = "" { didSet { filterContacts() } }
  var filteredContacts: [MemberDisplayItem] = []
  var isLoading: Bool = false
  var hasError: Bool = false
  var errorMessage: String = ""
  var isCreatingConversation: Bool = false

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

  func loadContacts() async {
    isLoading = true
    defer { isLoading = false }

    hasError = false
    errorMessage = ""

    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("NewConversation: missing membershipId, cannot load contacts")
      applyContactsLoadFailure(String(localized: "Missing membership identity"))
      return
    }
    guard let currentAccountId else {
      AppLogger.messaging.error("NewConversation: no accountId, cannot load contacts")
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
        accumulated.append(contentsOf: response.contacts.map { contact in
          MemberDisplayItem(
            id: contact.membershipID,
            accountId: contact.accountID,
            displayName: contact.displayName,
            handle: contact.handle,
            avatarUrl: contact.hasAvatarURL ? contact.avatarURL : nil,
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
          "NewConversation: failed to load contacts: \(error.logDescription, privacy: .public)")
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

  func createDirectConversation(with recipientMembershipId: Data) async -> Data? {
    guard let currentAccountId else {
      hasError = true
      errorMessage = String(localized: "Missing account information")
      AppLogger.messaging.error("NewConversation: missing accountId for createDirectConversation")
      return nil
    }
    guard let membershipId = settingsProvider()?.membership?.membershipId else {
      AppLogger.messaging.error("NewConversation: no membershipId for createDirectConversation")
      hasError = true
      errorMessage = String(localized: "Missing membership identity")
      return nil
    }
    isCreatingConversation = true
    defer { isCreatingConversation = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let result = await messagingService.createDirectConversation(
      accountId: currentAccountId,
      membershipId: membershipId.protobufBytes,
      recipientMembershipId: recipientMembershipId,
      connectId: connectId
    )
    switch result {
    case .ok(let response):
      hasError = false
      errorMessage = ""
      return response.conversation.conversationID
    case .err(let rpcError):
      AppLogger.messaging.error(
        "NewConversation: failed to create conversation: \(rpcError.logDescription, privacy: .public)"
      )
      hasError = true
      errorMessage = rpcError.userFacingMessage
      return nil
    }
  }

  func resetState() {
    contacts = []
    filteredContacts = []
    allContacts = []
    searchQuery = ""
    isLoading = false
    hasError = false
    errorMessage = ""
    isCreatingConversation = false
  }

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  private func filterContacts() {
    if searchQuery.isEmpty {
      filteredContacts = allContacts
    } else {
      let query = searchQuery.lowercased()
      filteredContacts = allContacts.filter {
        $0.displayName.lowercased().contains(query) || $0.handle.lowercased().contains(query)
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
      MemberDisplayItem(
        id: Data([5]), accountId: Data([5]), displayName: "Eva Martinez", handle: "eva",
        avatarUrl: nil, role: .member, joinedAt: nil),
      MemberDisplayItem(
        id: Data([6]), accountId: Data([6]), displayName: "Frank Lee", handle: "frank",
        avatarUrl: nil, role: .member, joinedAt: nil),
    ]
  }
}
