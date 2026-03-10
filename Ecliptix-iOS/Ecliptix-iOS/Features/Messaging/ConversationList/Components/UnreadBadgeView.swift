// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct UnreadBadgeView: View {

  let count: Int32

  var body: some View {
    Text(count > 99 ? "99+" : "\(count)")
      .font(.geist(.semiBold, size: 11))
      .foregroundColor(.white)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Color.ecliptixAccent)
      .clipShape(Capsule())
  }
}
