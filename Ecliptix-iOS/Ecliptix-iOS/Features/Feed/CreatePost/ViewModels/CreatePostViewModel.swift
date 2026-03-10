// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import os

@Observable @MainActor
final class CreatePostViewModel: Resettable {

  var textContent = ""
  var isPosting = false
  var hasError = false
  var errorMessage = ""

  let maxCharacters = 500

  var characterCount: Int { textContent.count }

  var canPost: Bool {
    !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && characterCount <= maxCharacters
      && !isPosting
  }

  var characterCountRatio: Double {
    guard maxCharacters > 0 else { return 0 }
    return Double(characterCount) / Double(maxCharacters)
  }

  let replyToPostId: Data?
  let replyToAuthorName: String?
  let quotePostId: Data?
  let mode: PostMode

  enum PostMode: Sendable {
    case original
    case reply
    case quote
  }

  private let feedService: FeedRpcService
  private let onPostCreated: () -> Void
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> UInt32

  private var currentAccountId: Data? {
    guard let uuid = settingsProvider()?.currentAccountId else { return nil }
    return uuid.protobufBytes
  }

  init(
    feedService: FeedRpcService,
    mode: PostMode = .original,
    replyToPostId: Data? = nil,
    replyToAuthorName: String? = nil,
    quotePostId: Data? = nil,
    onPostCreated: @escaping () -> Void,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> UInt32
  ) {
    self.feedService = feedService
    self.mode = mode
    self.replyToPostId = replyToPostId
    self.replyToAuthorName = replyToAuthorName
    self.quotePostId = quotePostId
    self.onPostCreated = onPostCreated
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
  }

  func submitPost() async {
    guard canPost else { return }
    isPosting = true
    hasError = false
    defer { isPosting = false }

    guard let currentAccountId,
      let membershipUUID = settingsProvider()?.membership?.membershipId
    else {
      hasError = true
      errorMessage = String(localized: "Unable to create post. Please try again.")
      return
    }

    let membershipId = membershipUUID.protobufBytes

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    let clientPostId = UUID().uuidString

    let result = await feedService.createPost(
      accountId: currentAccountId,
      membershipId: membershipId,
      textContent: textContent,
      media: [],
      visibility: .public,
      replyToPostId: replyToPostId,
      quotePostId: quotePostId,
      clientPostId: clientPostId,
      connectId: connectId
    )

    switch result {
    case .ok(let response):
      if response.isSuccess {
        AppLogger.feed.info(
          "Post created successfully, clientPostId=\(clientPostId, privacy: .private(mask: .hash))")
        onPostCreated()
      } else {
        hasError = true
        errorMessage = String(localized: "Failed to create post.")
      }
    case .err(let error):
      AppLogger.feed.error("CreatePost failed: \(error, privacy: .public)")
      hasError = true
      errorMessage = String(localized: "Failed to create post. Please try again.")
    }
  }

  func resetState() {
    textContent = ""
    isPosting = false
    hasError = false
    errorMessage = ""
  }
}
