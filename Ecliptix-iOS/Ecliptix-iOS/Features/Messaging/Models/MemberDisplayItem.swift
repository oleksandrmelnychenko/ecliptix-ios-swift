// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct MemberDisplayItem: Identifiable, Hashable, Sendable {

  let id: Data
  let accountId: Data
  let displayName: String
  let profileName: String
  let avatarUrl: String?
  var role: MemberRole
  let joinedAt: Date?

  enum MemberRole: Int, Sendable {
    case unspecified = 0
    case member = 1
    case admin = 2
    case owner = 3

    var displayLabel: String {
      switch self {
      case .unspecified, .member: ""
      case .admin: String(localized: "Admin")
      case .owner: String(localized: "Owner")
      }
    }
  }
}
