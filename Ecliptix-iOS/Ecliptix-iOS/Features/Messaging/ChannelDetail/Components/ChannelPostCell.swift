// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ChannelPostCell: View {

  let post: ChannelPostDisplayItem
  let isAdmin: Bool
  var onDelete: () -> Void

  private static let todayTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static let dateTimeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "dd/MM HH:mm"
    return formatter
  }()

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(post.authorSignature ?? post.authorName)
          .font(.geist(.semiBold, size: 14))
          .foregroundColor(.ecliptixAccent)
        Spacer()
        Text(formattedTime(post.sentAt))
          .font(.geistCaption2)
          .foregroundColor(.ecliptixTertiaryText)
      }

      if !post.textContent.isEmpty {
        Text(post.textContent)
          .font(.geist(.regular, size: 15))
          .foregroundColor(.ecliptixPrimaryText)
      }

      HStack(spacing: 16) {
        Label(formattedCount(post.viewCount), systemImage: "eye")
          .font(.geist(.regular, size: 12))
          .foregroundColor(.ecliptixTertiaryText)

        if post.forwardCount > 0 {
          Label(formattedCount(post.forwardCount), systemImage: "arrowshape.turn.up.right")
            .font(.geist(.regular, size: 12))
            .foregroundColor(.ecliptixTertiaryText)
        }

        Spacer()

        if post.isEdited {
          Text(String(localized: "edited"))
            .font(.geist(.regular, size: 11))
            .foregroundColor(.ecliptixTertiaryText)
        }
      }

      if !post.reactions.isEmpty {
        HStack(spacing: 4) {
          ForEach(post.reactions, id: \.emoji) { reaction in
            Text("\(reaction.emoji) \(reaction.count)")
              .font(.geist(.regular, size: 12))
              .padding(.horizontal, 6)
              .padding(.vertical, 2)
              .background(
                reaction.reactedByMe
                  ? Color.ecliptixAccent.opacity(0.15)
                  : Color.ecliptixSurface
              )
              .clipShape(Capsule())
              .overlay(
                Capsule()
                  .stroke(
                    reaction.reactedByMe
                      ? Color.ecliptixAccent.opacity(0.3)
                      : Color.ecliptixMutedStroke,
                    lineWidth: 0.5
                  )
              )
          }
        }
      }
    }
    .contextMenu {
      Button {
        UIPasteboard.general.string = post.textContent
      } label: {
        Label(String(localized: "Copy"), systemImage: "doc.on.doc")
      }

      if isAdmin {
        Button(role: .destructive) {
          onDelete()
        } label: {
          Label(String(localized: "Delete"), systemImage: "trash")
        }
      }
    }
  }

  private func formattedTime(_ date: Date) -> String {
    let formatter =
      Calendar.current.isDateInToday(date) ? Self.todayTimeFormatter : Self.dateTimeFormatter
    return formatter.string(from: date)
  }

  private func formattedCount(_ count: Int32) -> String {
    if count >= 1_000_000 { return "\(count / 1_000_000)M" }
    if count >= 1_000 { return "\(count / 1_000)K" }
    return "\(count)"
  }
}
