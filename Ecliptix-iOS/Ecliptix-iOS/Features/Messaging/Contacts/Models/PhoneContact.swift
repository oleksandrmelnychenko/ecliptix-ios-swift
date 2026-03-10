// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation

struct PhoneContact: Identifiable, Hashable, Sendable {

  let id: String
  let givenName: String
  let familyName: String
  let phoneNumbers: [String]
  let thumbnailData: Data?
  var ecliptixProfile: AccountProfile?

  var fullName: String {
    [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
  }

  var isOnEcliptix: Bool { ecliptixProfile != nil }

  var initials: String { fullName.initials }

  var primaryPhone: String { phoneNumbers.first ?? "" }

  func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }

  static func == (lhs: PhoneContact, rhs: PhoneContact) -> Bool {
    lhs.id == rhs.id
  }
}
