// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum FeedTimeline: Int, Sendable, CaseIterable {
  case forYou = 0
  case following = 1

  var title: String {
    switch self {
    case .forYou: String(localized: "For You")
    case .following: String(localized: "Following")
    }
  }
}
