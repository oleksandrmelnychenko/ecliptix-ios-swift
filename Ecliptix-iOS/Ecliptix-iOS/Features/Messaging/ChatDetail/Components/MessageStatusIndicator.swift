// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct MessageStatusIndicator: View {

  let status: MessageDisplayItem.DeliveryStatus

  private static let indicatorFont = Font.geist(.medium, size: 10)
  private static let failedFont = Font.geist(.medium, size: 11)

  var body: some View {
    Group {
      switch status {
      case .sending:
        Image(systemName: "clock")
          .font(Self.indicatorFont)
          .foregroundColor(.ecliptixTertiaryText)

      case .sent:
        Image(systemName: "checkmark")
          .font(Self.indicatorFont)
          .foregroundColor(.ecliptixTertiaryText)

      case .delivered:
        doubleCheck
          .foregroundColor(.ecliptixTertiaryText)

      case .read:
        doubleCheck
          .foregroundColor(.ecliptixAccent)

      case .failed:
        Image(systemName: "exclamationmark.circle.fill")
          .font(Self.failedFont)
          .foregroundColor(.ecliptixDanger)

      case .unspecified:
        EmptyView()
      }
    }
    .accessibilityHidden(true)
  }

  private var doubleCheck: some View {
    ZStack(alignment: .leading) {
      Image(systemName: "checkmark")
        .font(Self.indicatorFont)

      Image(systemName: "checkmark")
        .font(Self.indicatorFont)
        .offset(x: 5)
    }
    .frame(width: 18, height: 12)
  }
}
