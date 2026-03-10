// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PhoneContactRow: View {

  let contact: PhoneContact
  let onTap: () -> Void
  let onInvite: () -> Void

  var body: some View {
    Button(action: { contact.isOnEcliptix ? onTap() : onInvite() }) {
      HStack(spacing: 12) {
        avatar
        nameSection
        Spacer()
        trailingBadge
      }
      .padding(.vertical, 2)
    }
    .buttonStyle(.plain)
  }

  private var avatar: some View {
    ZStack {
      if let data = contact.thumbnailData, let uiImage = UIImage(data: data) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 44, height: 44)
          .clipShape(Circle())
      } else {
        Circle()
          .fill(Color.ecliptixAccent.opacity(0.15))
          .frame(width: 44, height: 44)
          .overlay {
            Text(contact.initials)
              .font(.geist(.semiBold, size: 15))
              .foregroundColor(.ecliptixAccent)
          }
      }
    }
  }

  private var nameSection: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(contact.fullName)
        .font(.geist(.medium, size: 16))
        .foregroundColor(.ecliptixPrimaryText)
      Text(contact.primaryPhone)
        .font(.geistCaption)
        .foregroundColor(.ecliptixSecondaryText)
    }
  }

  @ViewBuilder
  private var trailingBadge: some View {
    if contact.isOnEcliptix {
      Text(String(localized: "on Ecliptix"))
        .font(.geist(.medium, size: 12))
        .foregroundColor(.ecliptixAccent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.ecliptixAccent.opacity(0.12))
        .clipShape(Capsule())
    } else {
      Text(String(localized: "Invite"))
        .font(.geist(.medium, size: 13))
        .foregroundColor(.ecliptixAccent)
    }
  }
}
