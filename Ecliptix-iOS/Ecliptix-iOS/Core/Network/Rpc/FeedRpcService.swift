import CryptoKit
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import EcliptixProtos
import Foundation
import SwiftProtobuf
import os

final class FeedRpcService {

  private let pipeline: SecureUnaryPipeline

  init(
    transport: EventGatewayTransport,
    secureSessionClient: any SecureSessionClient & NetworkOutageControlling,
    secureStorageService: SecureStorageService,
    protocolStateStorage: ProtocolStateStorage,
    identityService: IdentityService
  ) {
    self.pipeline = SecureUnaryPipeline(
      transport: transport,
      secureSessionClient: secureSessionClient,
      log: AppLogger.feed,
      secureStorageService: secureStorageService,
      protocolStateStorage: protocolStateStorage,
      identityService: identityService
    )
  }

  func getFeed(
    accountId: Data,
    membershipId: Data,
    feedType: ProtoFeedType,
    pageSize: Int32,
    cursor: String,
    connectId: UInt32
  ) async -> Result<ProtoGetFeedResponse, RpcError> {
    var request = ProtoGetFeedRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.feedType = feedType
    if pageSize > 0 {
      request.pageSize = pageSize
    }
    if !cursor.isEmpty {
      request.cursor = cursor
    }
    AppLogger.feed.info(
      "GetFeed: start connectId=\(connectId, privacy: .public), feedType=\(feedType.rawValue, privacy: .public), pageSize=\(pageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .getFeed,
      request: request,
      connectId: connectId,
      label: "GetFeed"
    )
  }

  func createPost(
    accountId: Data,
    membershipId: Data,
    textContent: String,
    media: [ProtoPostMedia],
    visibility: ProtoPostVisibility,
    replyToPostId: Data?,
    quotePostId: Data?,
    clientPostId: String,
    connectId: UInt32
  ) async -> Result<ProtoCreatePostResponse, RpcError> {
    var request = ProtoCreatePostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.textContent = textContent
    request.media = media
    request.visibility = visibility
    if let replyToPostId {
      request.replyToPostID = replyToPostId
    }
    if let quotePostId {
      request.quotePostID = quotePostId
    }
    request.clientPostID = clientPostId
    AppLogger.feed.info(
      "CreatePost: start connectId=\(connectId, privacy: .public), clientPostId=\(clientPostId, privacy: .private(mask: .hash)), mediaCount=\(media.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .createPost,
      request: request,
      connectId: connectId,
      label: "CreatePost"
    )
  }

  func deletePost(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    connectId: UInt32
  ) async -> Result<ProtoDeletePostResponse, RpcError> {
    var request = ProtoDeletePostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    AppLogger.feed.info(
      "DeletePost: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .deletePost,
      request: request,
      connectId: connectId,
      label: "DeletePost"
    )
  }

  func editPost(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    textContent: String,
    connectId: UInt32
  ) async -> Result<ProtoEditPostResponse, RpcError> {
    var request = ProtoEditPostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    request.textContent = textContent
    AppLogger.feed.info(
      "EditPost: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .editPost,
      request: request,
      connectId: connectId,
      label: "EditPost"
    )
  }

  func likePost(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    connectId: UInt32
  ) async -> Result<ProtoLikePostResponse, RpcError> {
    var request = ProtoLikePostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    AppLogger.feed.info(
      "LikePost: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .likePost,
      request: request,
      connectId: connectId,
      label: "LikePost"
    )
  }

  func repost(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    connectId: UInt32
  ) async -> Result<ProtoRepostResponse, RpcError> {
    var request = ProtoRepostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    AppLogger.feed.info(
      "Repost: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .repost,
      request: request,
      connectId: connectId,
      label: "Repost"
    )
  }

  func bookmarkPost(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    connectId: UInt32
  ) async -> Result<ProtoBookmarkPostResponse, RpcError> {
    var request = ProtoBookmarkPostRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    AppLogger.feed.info(
      "BookmarkPost: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .bookmarkPost,
      request: request,
      connectId: connectId,
      label: "BookmarkPost"
    )
  }

  func getPostThread(
    accountId: Data,
    membershipId: Data,
    postId: Data,
    replyPageSize: Int32,
    replyCursor: String,
    connectId: UInt32
  ) async -> Result<ProtoGetPostThreadResponse, RpcError> {
    var request = ProtoGetPostThreadRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.postID = postId
    if replyPageSize > 0 {
      request.replyPageSize = replyPageSize
    }
    if !replyCursor.isEmpty {
      request.replyCursor = replyCursor
    }
    AppLogger.feed.info(
      "GetPostThread: start connectId=\(connectId, privacy: .public), postIdBytes=\(postId.count, privacy: .public), replyPageSize=\(replyPageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .getPostThread,
      request: request,
      connectId: connectId,
      label: "GetPostThread"
    )
  }

  func getUserPosts(
    accountId: Data,
    membershipId: Data,
    targetMembershipId: Data,
    pageSize: Int32,
    cursor: String,
    connectId: UInt32
  ) async -> Result<ProtoGetUserPostsResponse, RpcError> {
    var request = ProtoGetUserPostsRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.targetMembershipID = targetMembershipId
    if pageSize > 0 {
      request.pageSize = pageSize
    }
    if !cursor.isEmpty {
      request.cursor = cursor
    }
    AppLogger.feed.info(
      "GetUserPosts: start connectId=\(connectId, privacy: .public), pageSize=\(pageSize, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .getUserPosts,
      request: request,
      connectId: connectId,
      label: "GetUserPosts"
    )
  }

  func followUser(
    accountId: Data,
    membershipId: Data,
    targetMembershipId: Data,
    connectId: UInt32
  ) async -> Result<ProtoFollowUserResponse, RpcError> {
    var request = ProtoFollowUserRequest()
    request.accountID = accountId
    request.membershipID = membershipId
    request.targetMembershipID = targetMembershipId
    AppLogger.feed.info(
      "FollowUser: start connectId=\(connectId, privacy: .public)"
    )
    return await executeTypedUnary(
      serviceType: .followUser,
      request: request,
      connectId: connectId,
      label: "FollowUser"
    )
  }

  private func executeTypedUnary<Request: SwiftProtobuf.Message, Response: SwiftProtobuf.Message>(
    serviceType: RpcServiceType,
    request: Request,
    connectId: UInt32,
    label: String
  ) async -> Result<Response, RpcError> {
    let requestData: Data
    do {
      requestData = try request.serializedData()
    } catch {
      AppLogger.feed.error(
        "\(label): serialize failed connectId=\(connectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.serializationFailed("\(label) request"))
    }

    let decryptedResult = await pipeline.executeSecureUnary(
      serviceType: serviceType,
      plaintext: requestData,
      connectId: connectId
    )
    guard let decryptedPayload = decryptedResult.ok() else {
      AppLogger.feed.warning(
        "\(label): secure unary failed connectId=\(connectId, privacy: .public), error=\(decryptedResult.unwrapErr().logDescription, privacy: .public)"
      )
      return decryptedResult.propagateErr()
    }

    let response: Response
    do {
      response = try Response(serializedBytes: decryptedPayload)
    } catch {
      AppLogger.feed.error(
        "\(label): parse failed connectId=\(connectId, privacy: .public), error=\(error.localizedDescription, privacy: .public)"
      )
      return .err(.deserializationFailed("\(label) response: \(error.localizedDescription)"))
    }
    AppLogger.feed.info(
      "\(label): success connectId=\(connectId, privacy: .public)"
    )
    return .ok(response)
  }
}
