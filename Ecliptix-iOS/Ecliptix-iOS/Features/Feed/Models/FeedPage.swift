// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct FeedPage: Sendable {

  let posts: [PostDisplayItem]
  let hasMore: Bool
  let isFromCache: Bool
}
