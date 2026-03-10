// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ConversationCellView: View {

  let conversation: ConversationDisplayItem

  var body: some View {
    HStack(spacing: 12) {
      avatar
      content
    }
    .padding(.vertical, 6)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(conversationAccessibilityLabel)
  }

  private var conversationAccessibilityLabel: Text {
    var parts = [conversation.title]
    if !conversation.lastMessagePreview.isEmpty {
      parts.append(conversation.lastMessagePreview)
    }
    if conversation.unreadCount > 0 {
      parts.append(String(format: String(localized: "%d unread"), conversation.unreadCount))
    }
    if let date = conversation.lastMessageDate {
      parts.append(formattedDate(date))
    }
    return Text(parts.joined(separator: ", "))
  }

  private var avatar: some View {
    ZStack {
      Circle()
        .fill(Color.ecliptixAccent.gradient)
        .frame(width: 52, height: 52)

      if conversation.isChannel {
        Image(systemName: "megaphone.fill")
          .font(.system(size: 18, weight: .semibold))
          .foregroundStyle(.white)
      } else {
        Text(conversation.title.initials)
          .font(.geist(.semiBold, size: 18))
          .foregroundStyle(.white)
      }
    }
    .accessibilityHidden(true)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 4) {
      topRow
      bottomRow
    }
  }

  private var topRow: some View {
    HStack {
      Text(conversation.title)
        .font(.geist(.semiBold, size: 16))
        .foregroundColor(.ecliptixPrimaryText)
        .lineLimit(1)

      Spacer()

      if let date = conversation.lastMessageDate {
        Text(formattedDate(date))
          .font(.geistCaption2)
          .foregroundColor(
            conversation.unreadCount > 0
              ? .ecliptixAccent
              : .ecliptixTertiaryText
          )
      }
    }
  }

  private var bottomRow: some View {
    HStack {
      messagePreview
      Spacer()
      badges
    }
  }

  private var messagePreview: some View {
    HStack(spacing: 0) {
      if (conversation.isGroup || conversation.isChannel) && !conversation.lastMessageSenderName.isEmpty {
        Text("\(conversation.lastMessageSenderName): ")
          .font(.geistFootnote)
          .foregroundColor(.ecliptixSecondaryText)
      }

      Text(contentTypePrefix + conversation.lastMessagePreview)
        .font(.geistFootnote)
        .foregroundColor(.ecliptixSecondaryText)
        .lineLimit(1)
    }
  }

  private var badges: some View {
    HStack(spacing: 6) {
      if conversation.isMuted {
        Image(systemName: "bell.slash.fill")
          .font(.geist(.regular, size: 12))
          .foregroundColor(.ecliptixTertiaryText)
      }

      if conversation.unreadCount > 0 {
        UnreadBadgeView(count: conversation.unreadCount)
      }
    }
  }

  private var contentTypePrefix: String {
    switch conversation.lastMessageContentType {
    case .image: return "📷 "
    case .video: return "🎬 "
    case .audio: return "🎤 "
    case .file: return "📎 "
    case .location: return "📍 "
    case .contact: return "👤 "
    default: return ""
    }
  }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
  }()

  private static let weekdayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "EEE"
    return f
  }()

  private static let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "dd/MM"
    return f
  }()

  private func formattedDate(_ date: Date) -> String {
    let calendar = Calendar.current
    let now = Date()

    if calendar.isDateInToday(date) {
      return Self.timeFormatter.string(from: date)
    }

    if calendar.isDateInYesterday(date) {
      return String(localized: "Yesterday")
    }

    let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
    if date >= startOfWeek {
      return Self.weekdayFormatter.string(from: date)
    }

    return Self.shortDateFormatter.string(from: date)
  }
}
