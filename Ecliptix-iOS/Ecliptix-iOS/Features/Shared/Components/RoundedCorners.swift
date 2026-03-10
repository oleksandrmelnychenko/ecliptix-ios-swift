// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

extension View {

  func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
    let topLeading = corners.contains(.topLeft) ? radius : 0
    let topTrailing = corners.contains(.topRight) ? radius : 0
    let bottomLeading = corners.contains(.bottomLeft) ? radius : 0
    let bottomTrailing = corners.contains(.bottomRight) ? radius : 0
    return clipShape(
      UnevenRoundedRectangle(
        topLeadingRadius: topLeading,
        bottomLeadingRadius: bottomLeading,
        bottomTrailingRadius: bottomTrailing,
        topTrailingRadius: topTrailing,
        style: .continuous
      )
    )
  }
}
