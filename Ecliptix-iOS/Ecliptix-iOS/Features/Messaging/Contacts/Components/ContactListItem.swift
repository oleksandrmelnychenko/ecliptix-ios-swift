// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ContactListItem: View {

  let contact: MemberDisplayItem

  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Circle()
          .fill(Color.ecliptixAccent.opacity(0.15))
          .frame(width: 44, height: 44)
        Text(initials)
          .font(.geist(.semiBold, size: 15))
          .foregroundColor(.ecliptixAccent)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(contact.displayName)
          .font(.geist(.medium, size: 16))
          .foregroundColor(.ecliptixPrimaryText)
        Text("@\(contact.profileName)")
          .font(.geistCaption)
          .foregroundColor(.ecliptixSecondaryText)
      }
    }
    .padding(.vertical, 2)
  }

  private var initials: String {
    contact.displayName.initials
  }
}
