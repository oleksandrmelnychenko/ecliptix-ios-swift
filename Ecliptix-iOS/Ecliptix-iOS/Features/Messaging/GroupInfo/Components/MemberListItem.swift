// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct MemberListItem: View {

  let member: MemberDisplayItem
  let isAdmin: Bool
  var onTap: (() -> Void)?
  var onRemove: (() -> Void)?

  var body: some View {
    Button {
      onTap?()
    } label: {
      HStack(spacing: 12) {
        ZStack {
          Circle()
            .fill(Color.ecliptixAccent.opacity(0.15))
            .frame(width: 40, height: 40)
          Text(initials)
            .font(.geist(.semiBold, size: 14))
            .foregroundColor(.ecliptixAccent)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(member.displayName)
            .font(.geist(.medium, size: 15))
            .foregroundColor(.ecliptixPrimaryText)
          Text("@\(member.handle)")
            .font(.geistCaption)
            .foregroundColor(.ecliptixSecondaryText)
        }

        Spacer()

        if !member.role.displayLabel.isEmpty {
          Text(member.role.displayLabel)
            .font(.geist(.medium, size: 11))
            .foregroundColor(member.role == .owner ? .ecliptixAccent : .ecliptixSecondaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
              (member.role == .owner ? Color.ecliptixAccent : Color.ecliptixSecondaryText)
                .opacity(0.1)
            )
            .clipShape(Capsule())
        }
      }
    }
    .buttonStyle(.plain)
    .swipeActions(edge: .trailing) {
      if isAdmin && member.role != .owner {
        if let onRemove {
          Button(role: .destructive) {
            onRemove()
          } label: {
            Label(String(localized: "Remove"), systemImage: "person.badge.minus")
          }
        }
      }
    }
  }

  private var initials: String {
    member.displayName.initials
  }
}
