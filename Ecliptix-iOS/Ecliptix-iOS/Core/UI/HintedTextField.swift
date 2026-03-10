// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct HintedTextField: View {

  let placeholder: String
  @Binding var text: String
  var hint: String = ""
  var error: String = ""
  var isSecure: Bool = false
  var isDisabled: Bool = false
  var prefix: String? = nil
  var keyboardType: UIKeyboardType = .default
  var textContentType: UITextContentType? = nil
  var autocapitalization: TextInputAutocapitalization = .sentences
  var disableAutocorrection: Bool = false
  var onSubmit: (() -> Void)? = nil

  @FocusState private var isFocused: Bool

  private var hasError: Bool { !error.isEmpty }
  private var hasHint: Bool { !hint.isEmpty }

  private var borderColor: Color {
    if hasError { return .ecliptixDanger }
    if isFocused { return .ecliptixAccent }
    return .ecliptixMutedStroke
  }

  private var borderWidth: CGFloat {
    (isFocused || hasError) ? 1.5 : 1
  }

  private var shadowColor: Color {
    if hasError { return .ecliptixDanger.opacity(0.25) }
    if isFocused { return .ecliptixAccent.opacity(0.2) }
    return .clear
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      inputField
      hintOrError
    }
    .animation(.ecliptixSnappy, value: hasError)
    .animation(.ecliptixSnappy, value: isFocused)
  }

  private var inputField: some View {
    HStack(spacing: 0) {
      if let prefix {
        Text(prefix)
          .font(.geist(.semiBold, size: 17))
          .foregroundColor(.ecliptixSecondaryText)
          .padding(.leading, 14)
        Rectangle()
          .fill(Color.ecliptixMutedStroke)
          .frame(width: 1)
          .padding(.vertical, 10)
          .padding(.horizontal, 10)
          .opacity(0.5)
      }
      Group {
        if isSecure {
          SecureField(placeholder, text: $text)
        } else {
          TextField(placeholder, text: $text)
        }
      }
      .font(.geistBody)
      .foregroundColor(.ecliptixPrimaryText)
      .tint(.ecliptixAccent)
      .keyboardType(keyboardType)
      .textContentType(textContentType)
      .textInputAutocapitalization(autocapitalization)
      .autocorrectionDisabled(disableAutocorrection)
      .focused($isFocused)
      .disabled(isDisabled)
      .padding(.horizontal, prefix == nil ? 14 : 0)
      .padding(.trailing, prefix != nil ? 14 : 0)
      .onSubmit { onSubmit?() }
    }
    .frame(minHeight: 48)
    .background(Color.ecliptixSurfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10)
        .stroke(borderColor, lineWidth: borderWidth)
    )
    .shadow(color: shadowColor, radius: 8, y: 2)
  }

  @ViewBuilder
  private var hintOrError: some View {
    if hasError {
      HStack(spacing: 5) {
        Text(error)
          .font(.geistCaption)
          .foregroundColor(.ecliptixDanger)
      }
      .transition(.opacity)
    } else if hasHint {
      Text(hint)
        .font(.geistCaption)
        .foregroundColor(.ecliptixSecondaryText)
        .transition(.opacity)
    }
  }
}
