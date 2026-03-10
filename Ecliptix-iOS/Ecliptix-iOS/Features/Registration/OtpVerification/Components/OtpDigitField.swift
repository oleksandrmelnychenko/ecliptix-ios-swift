// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct OtpDigitField: View {

  @Binding var digit: String
  let isFocused: Bool
  let index: Int
  let totalDigits: Int
  let onTap: () -> Void
  let onDigitEntered: () -> Void
  let onBackspace: () -> Void

  init(
    digit: Binding<String>, isFocused: Bool, index: Int = 0,
    totalDigits: Int = AppConstants.Otp.defaultOtpCodeLength, onTap: @escaping () -> Void,
    onDigitEntered: @escaping () -> Void, onBackspace: @escaping () -> Void
  ) {
    self._digit = digit
    self.isFocused = isFocused
    self.index = index
    self.totalDigits = totalDigits
    self.onTap = onTap
    self.onDigitEntered = onDigitEntered
    self.onBackspace = onBackspace
  }

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(
          isFocused ? Color.ecliptixAccent : Color.ecliptixMutedStroke,
          lineWidth: isFocused ? 2 : 1
        )
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color.ecliptixSurfaceElevated)
        )
        .frame(width: 48, height: 56)
      Text(digit)
        .font(.geistTitle2)
        .foregroundColor(.ecliptixPrimaryText)
      if isFocused && digit.isEmpty {
        Rectangle()
          .fill(Color.ecliptixAccent)
          .frame(width: 2, height: 32)
          .opacity(0.8)
      }
    }
    .onTapGesture {
      onTap()
    }
    .accessibilityLabel(Text("Digit \(index + 1) of \(totalDigits)"))
    .accessibilityValue(digit.isEmpty ? Text("Empty") : Text(digit))
    .onChange(of: digit) { _, newValue in
      if newValue.count > 1 {
        digit = String(newValue.prefix(1))
      }
      if !newValue.isEmpty {
        onDigitEntered()
      }
    }
  }
}
