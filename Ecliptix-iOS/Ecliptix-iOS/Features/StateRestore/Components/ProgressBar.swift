// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ProgressBar: View {

  let current: Int
  let total: Int
  var progress: CGFloat {
    guard total > 0 else { return 0 }
    return CGFloat(current) / CGFloat(total)
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack(alignment: .leading) {
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.white.opacity(0.3))
          .frame(height: 8)
        RoundedRectangle(cornerRadius: 4)
          .fill(Color.white)
          .frame(width: geometry.size.width * progress, height: 8)
          .animation(.ecliptixSmooth, value: progress)
      }
    }
    .frame(height: 8)
    .accessibilityValue(Text("\(Int(progress * 100)) percent"))
    .accessibilityLabel(Text("Progress"))
  }
}
