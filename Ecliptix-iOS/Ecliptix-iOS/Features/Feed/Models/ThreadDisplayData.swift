// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct ThreadDisplayData: Sendable {

  let ancestorChain: [PostDisplayItem]
  var focalPost: PostDisplayItem
  var replies: [PostDisplayItem]
  var hasMoreReplies: Bool
  var nextReplyCursor: String
}
