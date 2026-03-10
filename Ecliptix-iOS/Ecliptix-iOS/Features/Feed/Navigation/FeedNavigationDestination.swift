// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum FeedNavigationDestination: Hashable {
  case postDetail(postId: Data)
  case createPost
  case createReply(parentPostId: Data, parentAuthorName: String)
  case createQuote(quotedPostId: Data)
  case userProfile(membershipId: Data)
  case postThread(postId: Data)
}
