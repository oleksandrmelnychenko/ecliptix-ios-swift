// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ChatInputBar: View {

  @Binding var text: String
  let isSending: Bool
  var isInputFocused: FocusState<Bool>.Binding
  let onSend: () -> Void
  let onAttach: () -> Void

  private var canSend: Bool {
    !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
  }

  var body: some View {
    HStack(alignment: .bottom, spacing: 10) {
      attachmentButton

      textField

      sendButton
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(Color.ecliptixSurface)
  }

  private var attachmentButton: some View {
    Button(action: onAttach) {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 28))
        .foregroundColor(.ecliptixSecondaryText)
    }
    .buttonStyle(.plain)
    .frame(width: 44, height: 44)
    .accessibilityLabel(Text(String(localized: "Attach file")))
    .accessibilityHint(Text(String(localized: "Opens attachment picker")))
  }

  private var textField: some View {
    TextField(
      String(localized: "Message"),
      text: $text,
      axis: .vertical
    )
    .font(.geistBody)
    .lineLimit(1...6)
    .focused(isInputFocused)
    .ecliptixInput(cornerRadius: 20)
  }

  private var sendButton: some View {
    Button(action: onSend) {
      ZStack {
        Circle()
          .fill(
            canSend
              ? LinearGradient(
                colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
              : LinearGradient(
                colors: [Color.ecliptixDisabled],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              )
          )
          .frame(width: 36, height: 36)
          .accessibilityHidden(true)

        if isSending {
          ProgressView()
            .tint(.white)
            .scaleEffect(0.7)
        } else {
          Image(systemName: "arrow.up")
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(canSend ? .ecliptixPrimaryButtonText : .ecliptixTertiaryText)
            .symbolEffect(.bounce, value: canSend)
        }
      }
    }
    .buttonStyle(.plain)
    .frame(width: 44, height: 44)
    .disabled(!canSend)
    .animation(.ecliptixSnappy, value: canSend)
    .accessibilityLabel(
      Text(isSending ? String(localized: "Sending") : String(localized: "Send message")))
  }
}
