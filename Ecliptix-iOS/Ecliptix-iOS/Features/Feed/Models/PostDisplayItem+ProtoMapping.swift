// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf

extension PostDisplayItem {

  static func from(proto: ProtoPost, currentMembershipId: Data) -> PostDisplayItem {
    PostDisplayItem(
      id: proto.postID,
      author: AuthorDisplay.from(proto: proto.author),
      postType: PostType(rawValue: proto.postType.rawValue) ?? .original,
      textContent: proto.textContent,
      media: proto.media.map { MediaDisplay.from(proto: $0) },
      quotedPost: proto.hasQuotedPost ? QuotedPostDisplay.from(proto: proto.quotedPost) : nil,
      repostedPost: proto.hasRepostedPost
        ? RepostedPostDisplay.from(proto: proto.repostedPost) : nil,
      metrics: MetricsDisplay.from(proto: proto.metrics),
      interaction: InteractionDisplay.from(proto: proto.interaction),
      createdAt: proto.createdAt.date,
      editedAt: proto.hasEditedAt ? proto.editedAt.date : nil,
      isDeleted: proto.isDeleted,
      parentPostId: proto.hasParentPostID ? proto.parentPostID : nil,
      replyDepth: Int(proto.replyDepth)
    )
  }
}

extension PostDisplayItem.AuthorDisplay {

  static func from(proto: ProtoPostAuthor) -> Self {
    PostDisplayItem.AuthorDisplay(
      membershipId: proto.membershipID,
      accountId: proto.accountID,
      displayName: proto.displayName,
      profileName: proto.profileName,
      avatarUrl: proto.hasAvatarURL ? proto.avatarURL : nil,
      isVerified: proto.isVerified
    )
  }
}

extension PostDisplayItem.MediaDisplay {

  static func from(proto: ProtoPostMedia) -> Self {
    PostDisplayItem.MediaDisplay(
      id: proto.mediaID,
      url: proto.url,
      thumbnailUrl: proto.hasThumbnailURL ? proto.thumbnailURL : nil,
      mimeType: proto.mimeType,
      width: proto.hasWidth ? Int(proto.width) : nil,
      height: proto.hasHeight ? Int(proto.height) : nil,
      durationSeconds: proto.hasDurationSeconds ? Int(proto.durationSeconds) : nil,
      altText: proto.hasAltText ? proto.altText : nil,
      sortOrder: Int(proto.sortOrder)
    )
  }
}

extension PostDisplayItem.MetricsDisplay {

  static func from(proto: ProtoPostMetrics) -> Self {
    PostDisplayItem.MetricsDisplay(
      replyCount: proto.replyCount,
      repostCount: proto.repostCount,
      likeCount: proto.likeCount,
      quoteCount: proto.quoteCount,
      viewCount: proto.viewCount,
      bookmarkCount: proto.bookmarkCount
    )
  }
}

extension PostDisplayItem.InteractionDisplay {

  static func from(proto: ProtoPostInteractionState) -> Self {
    PostDisplayItem.InteractionDisplay(
      liked: proto.liked,
      reposted: proto.reposted,
      bookmarked: proto.bookmarked
    )
  }
}

extension PostDisplayItem.QuotedPostDisplay {

  static func from(proto: ProtoPost) -> Self {
    PostDisplayItem.QuotedPostDisplay(
      id: proto.postID,
      author: PostDisplayItem.AuthorDisplay.from(proto: proto.author),
      textContent: proto.textContent,
      media: proto.media.map { PostDisplayItem.MediaDisplay.from(proto: $0) },
      createdAt: proto.createdAt.date
    )
  }
}

extension PostDisplayItem.RepostedPostDisplay {

  static func from(proto: ProtoPost) -> Self {
    PostDisplayItem.RepostedPostDisplay(
      id: proto.postID,
      author: PostDisplayItem.AuthorDisplay.from(proto: proto.author),
      textContent: proto.textContent,
      media: proto.media.map { PostDisplayItem.MediaDisplay.from(proto: $0) },
      metrics: PostDisplayItem.MetricsDisplay.from(proto: proto.metrics),
      interaction: PostDisplayItem.InteractionDisplay.from(proto: proto.interaction),
      createdAt: proto.createdAt.date
    )
  }
}
