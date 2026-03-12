// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum MessagesNavigationDestination: Hashable {
  case chatDetail(conversationId: Data)
  case newConversation
  case newGroup
  case groupCreation(memberIds: [Data])
  case conversationInfo(conversationId: Data)
  case profile(membershipId: Data, displayName: String? = nil, handle: String? = nil)
  case contactSearch
  case phoneContacts
  case channelFeed(channelId: Data)
  case channelInfo(channelId: Data)
  case channelCreation
  case addMembers(conversationId: Data)
}
