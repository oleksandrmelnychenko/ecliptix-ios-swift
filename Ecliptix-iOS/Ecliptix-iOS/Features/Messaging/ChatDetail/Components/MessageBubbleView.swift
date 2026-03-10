// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct MessageBubbleView: View {

  let message: MessageDisplayItem
  let isGroupChat: Bool

  private let ownBubbleColor = Color.ecliptixAccent
  private let otherBubbleColor = Color.ecliptixSurface

  var body: some View {
    HStack(alignment: .bottom, spacing: 6) {
      if message.isOwnMessage {
        Spacer(minLength: 60)
      }

      VStack(alignment: message.isOwnMessage ? .trailing : .leading, spacing: 3) {
        if isGroupChat && !message.isOwnMessage {
          Text(message.senderDisplayName)
            .font(.geistCaption)
            .foregroundColor(.ecliptixAccent)
            .padding(.leading, 12)
        }

        if let replyPreview = message.replyToPreview {
          replyPreviewView(
            senderName: message.replyToSenderName,
            preview: replyPreview
          )
        }

        bubbleContent

        HStack(spacing: 4) {
          if message.isEdited {
            Text(String(localized: "edited"))
              .font(.geistCaption2)
              .foregroundColor(.ecliptixTertiaryText)
          }

          Text(formattedTime)
            .font(.geistCaption2)
            .foregroundColor(.ecliptixTertiaryText)

          if message.isOwnMessage {
            MessageStatusIndicator(status: message.deliveryStatus)
          }
        }
        .padding(.horizontal, 4)

        if !message.reactions.isEmpty {
          reactionsView
        }
      }

      if !message.isOwnMessage {
        Spacer(minLength: 60)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(messageAccessibilityLabel)
  }

  private var messageAccessibilityLabel: Text {
    var parts: [String] = []
    if isGroupChat && !message.isOwnMessage {
      parts.append(message.senderDisplayName)
    }
    if message.isDeleted {
      parts.append(String(localized: "This message was deleted"))
    } else {
      parts.append(message.textContent)
    }
    if message.isEdited {
      parts.append(String(localized: "edited"))
    }
    parts.append(formattedTime)
    if message.isOwnMessage {
      parts.append(statusAccessibilityLabel)
    }
    return Text(parts.joined(separator: ", "))
  }

  private var statusAccessibilityLabel: String {
    switch message.deliveryStatus {
    case .sending: String(localized: "Sending")
    case .sent: String(localized: "Sent")
    case .delivered: String(localized: "Delivered")
    case .read: String(localized: "Read")
    case .failed: String(localized: "Failed to send")
    case .unspecified: ""
    }
  }

  private var bubbleContent: some View {
    Group {
      if message.isDeleted {
        deletedContent
      } else {
        switch message.contentType {
        case .text:
          textContent
        case .image:
          mediaPlaceholder(icon: "photo", label: String(localized: "Photo"))
        case .video:
          mediaPlaceholder(icon: "video", label: String(localized: "Video"))
        case .audio:
          mediaPlaceholder(icon: "waveform", label: String(localized: "Voice message"))
        case .file:
          mediaPlaceholder(icon: "doc", label: message.mediaFilename ?? String(localized: "File"))
        case .location:
          mediaPlaceholder(icon: "location", label: String(localized: "Location"))
        case .contact:
          mediaPlaceholder(icon: "person.crop.circle", label: String(localized: "Contact"))
        case .system, .unspecified:
          systemContent
        }
      }
    }
  }

  private var textContent: some View {
    Text(message.textContent)
      .font(.geistBody)
      .foregroundColor(message.isOwnMessage ? .white : .ecliptixPrimaryText)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(message.isOwnMessage ? ownBubbleColor : otherBubbleColor)
      .clipShape(bubbleShape)
  }

  private var deletedContent: some View {
    HStack(spacing: 6) {
      Image(systemName: "nosign")
        .font(.system(size: 12))
      Text(String(localized: "This message was deleted"))
        .font(.geist(.regular, size: 14))
        .italic()
    }
    .foregroundColor(.ecliptixTertiaryText)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(Color.ecliptixSurface.opacity(0.6))
    .clipShape(bubbleShape)
  }

  private var systemContent: some View {
    Text(message.textContent)
      .font(.geistCaption)
      .foregroundColor(.ecliptixSecondaryText)
      .padding(.horizontal, 14)
      .padding(.vertical, 8)
      .background(Color.ecliptixSurface.opacity(0.5))
      .clipShape(Capsule())
      .frame(maxWidth: .infinity)
  }

  private func mediaPlaceholder(icon: String, label: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 14))
      Text(label)
        .font(.geist(.regular, size: 14))
    }
    .foregroundColor(message.isOwnMessage ? .white : .ecliptixPrimaryText)
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(message.isOwnMessage ? ownBubbleColor : otherBubbleColor)
    .clipShape(bubbleShape)
  }

  private func replyPreviewView(senderName: String?, preview: String) -> some View {
    HStack(spacing: 8) {
      RoundedRectangle(cornerRadius: 1.5)
        .fill(Color.ecliptixAccent)
        .frame(width: 3, height: 28)

      VStack(alignment: .leading, spacing: 1) {
        if let senderName {
          Text(senderName)
            .font(.geist(.semiBold, size: 11))
            .foregroundColor(.ecliptixAccent)
            .lineLimit(1)
        }
        Text(preview)
          .font(.geist(.regular, size: 11))
          .foregroundColor(
            message.isOwnMessage
              ? .white.opacity(0.8)
              : .ecliptixSecondaryText
          )
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      (message.isOwnMessage
        ? Color.white.opacity(0.15)
        : Color.ecliptixSurface.opacity(0.6))
    )
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.horizontal, 4)
    .padding(.top, 4)
  }

  private var reactionsView: some View {
    HStack(spacing: 4) {
      ForEach(message.reactions, id: \.emoji) { reaction in
        HStack(spacing: 2) {
          Text(reaction.emoji)
            .font(.geist(.regular, size: 14))
          if reaction.count > 1 {
            Text("\(reaction.count)")
              .font(.geistCaption2)
              .foregroundColor(.ecliptixSecondaryText)
          }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
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

  private var bubbleShape: UnevenRoundedRectangle {
    if message.isOwnMessage {
      UnevenRoundedRectangle(
        topLeadingRadius: 16,
        bottomLeadingRadius: 16,
        bottomTrailingRadius: 4,
        topTrailingRadius: 16
      )
    } else {
      UnevenRoundedRectangle(
        topLeadingRadius: 16,
        bottomLeadingRadius: 4,
        bottomTrailingRadius: 16,
        topTrailingRadius: 16
      )
    }
  }

  private static let timeFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
  }()

  private var formattedTime: String {
    Self.timeFormatter.string(from: message.sentAt)
  }
}
