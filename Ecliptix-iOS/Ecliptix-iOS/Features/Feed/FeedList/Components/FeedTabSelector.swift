// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct FeedTabSelector: View {

  @Binding var selectedTab: FeedTimeline
  @Namespace private var animation

  var body: some View {
    HStack(spacing: 0) {
      ForEach(FeedTimeline.allCases, id: \.rawValue) { tab in
        Button {
          withAnimation(.ecliptixSnappy) { selectedTab = tab }
        } label: {
          VStack(spacing: 8) {
            Text(tab.title)
              .font(.geist(selectedTab == tab ? .semiBold : .regular, size: 15))
              .foregroundStyle(
                selectedTab == tab ? Color.ecliptixPrimaryText : Color.ecliptixSecondaryText)

            if selectedTab == tab {
              Capsule()
                .fill(Color.ecliptixAccent)
                .frame(height: 3)
                .matchedGeometryEffect(id: "feed_tab_indicator", in: animation)
            } else {
              Capsule()
                .fill(Color.clear)
                .frame(height: 3)
            }
          }
          .frame(maxWidth: .infinity)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
      }
    }
    .padding(.horizontal, 16)
    .background(Color.ecliptixSurface)
  }
}
