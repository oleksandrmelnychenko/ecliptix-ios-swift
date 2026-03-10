// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum MessagesNavigationDestination: Hashable {
  case chatDetail(conversationId: Data)
  case newConversation
  case newGroup
  case groupCreation(memberIds: [Data])
  case conversationInfo(conversationId: Data)
  case userProfile(membershipId: Data)
  case contactSearch
  case phoneContacts
  case channelFeed(channelId: Data)
  case channelInfo(channelId: Data)
  case channelCreation
}
