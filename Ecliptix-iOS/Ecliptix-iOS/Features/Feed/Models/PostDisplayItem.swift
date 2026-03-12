// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import SwiftUI

struct PostDisplayItem: Identifiable, Hashable, Sendable {

  let id: Data
  let author: AuthorDisplay
  let postType: PostType
  let textContent: String
  let media: [MediaDisplay]
  let quotedPost: QuotedPostDisplay?
  let repostedPost: RepostedPostDisplay?
  var metrics: MetricsDisplay
  var interaction: InteractionDisplay
  let createdAt: Date
  let editedAt: Date?
  let isDeleted: Bool
  let parentPostId: Data?
  let replyDepth: Int

  enum PostType: Int, Sendable {
    case unspecified = 0
    case original = 1
    case reply = 2
    case repost = 3
    case quote = 4
  }

  struct AuthorDisplay: Hashable, Sendable {

    let membershipId: Data
    let accountId: Data
    let displayName: String
    let handle: String
    let avatarUrl: String?
    let isVerified: Bool
  }

  struct MediaDisplay: Hashable, Sendable, Identifiable {

    let id: String
    let url: String
    let thumbnailUrl: String?
    let mimeType: String
    let width: Int?
    let height: Int?
    let durationSeconds: Int?
    let altText: String?
    let sortOrder: Int

    var isImage: Bool { mimeType.hasPrefix("image/") }
    var isVideo: Bool { mimeType.hasPrefix("video/") }
    var aspectRatio: CGFloat? {
      guard let w = width, let h = height, h > 0 else { return nil }
      return CGFloat(w) / CGFloat(h)
    }
  }

  struct MetricsDisplay: Hashable, Sendable {

    var replyCount: Int64
    var repostCount: Int64
    var likeCount: Int64
    var quoteCount: Int64
    var viewCount: Int64
    var bookmarkCount: Int64
  }

  struct InteractionDisplay: Hashable, Sendable {

    var liked: Bool
    var reposted: Bool
    var bookmarked: Bool
  }

  struct QuotedPostDisplay: Hashable, Sendable {

    let id: Data
    let author: AuthorDisplay
    let textContent: String
    let media: [MediaDisplay]
    let createdAt: Date
  }

  struct RepostedPostDisplay: Hashable, Sendable {

    let id: Data
    let author: AuthorDisplay
    let textContent: String
    let media: [MediaDisplay]
    let metrics: MetricsDisplay
    let interaction: InteractionDisplay
    let createdAt: Date
  }
}
