// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Contacts
import Foundation
import os.log

final class PhoneContactsService: Sendable {

  var authorizationStatus: CNAuthorizationStatus {
    CNContactStore.authorizationStatus(for: .contacts)
  }

  func requestAccess() async -> Bool {
    do {
      let granted = try await CNContactStore().requestAccess(for: .contacts)
      AppLogger.app.info("PhoneContacts: access request result=\(granted, privacy: .public)")
      return granted
    } catch {
      AppLogger.app.error(
        "PhoneContacts: access request failed, error=\(error.localizedDescription, privacy: .public)"
      )
      return false
    }
  }

  func fetchContacts() async throws -> [PhoneContact] {
    let keysToFetch: [CNKeyDescriptor] = [
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactThumbnailImageDataKey as CNKeyDescriptor,
      CNContactIdentifierKey as CNKeyDescriptor,
    ]
    let request = CNContactFetchRequest(keysToFetch: keysToFetch)
    request.sortOrder = .givenName

    var contacts: [PhoneContact] = []
    contacts.reserveCapacity(256)
    let store = CNContactStore()
    try store.enumerateContacts(with: request) { cnContact, _ in
      let phoneNumbers = cnContact.phoneNumbers.compactMap { phone -> String? in
        let normalized = Self.normalizePhoneNumber(phone.value.stringValue)
        return normalized.isEmpty ? nil : normalized
      }
      guard !phoneNumbers.isEmpty else { return }
      let thumbnail: Data? = {
        guard let data = cnContact.thumbnailImageData else { return nil }
        return data.count <= 100_000 ? data : nil
      }()
      let contact = PhoneContact(
        id: cnContact.identifier,
        givenName: cnContact.givenName,
        familyName: cnContact.familyName,
        phoneNumbers: phoneNumbers,
        thumbnailData: thumbnail
      )
      contacts.append(contact)
    }
    return contacts
  }

  private static func normalizePhoneNumber(_ raw: String) -> String {
    var digits = raw.filter { $0.isNumber || $0 == "+" }
    if digits.isEmpty { return "" }
    if !digits.hasPrefix("+") {
      digits = "+\(digits)"
    }
    return digits
  }
}
