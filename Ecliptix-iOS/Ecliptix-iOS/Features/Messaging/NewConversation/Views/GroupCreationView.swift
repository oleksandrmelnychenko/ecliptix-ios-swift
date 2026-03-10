// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct GroupCreationView: View {

  @State var viewModel: GroupCreationViewModel
  var onGroupCreated: (Data) -> Void

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      VStack(spacing: 24) {
        groupAvatar
          .padding(.top, 24)

        VStack(spacing: 16) {
          TextField(String(localized: "Group Name"), text: $viewModel.groupName)
            .font(.geistBody)
            .ecliptixInput()

          TextField(
            String(localized: "Group Description"), text: $viewModel.groupDescription,
            axis: .vertical
          )
          .font(.geistBody)
          .lineLimit(3...6)
          .ecliptixInput()

          Toggle(isOn: $viewModel.shieldMode) {
            VStack(alignment: .leading, spacing: 4) {
              Text(String(localized: "Shield Mode"))
                .font(.geist(.semiBold, size: 15))
                .foregroundColor(.ecliptixPrimaryText)
              Text(String(localized: "Create this group as a shielded EPP conversation."))
                .font(.geistFootnote)
                .foregroundColor(.ecliptixSecondaryText)
            }
          }
          .toggleStyle(.switch)
          .padding(.horizontal, 14)
          .padding(.vertical, 12)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .fill(Color.ecliptixSurface.opacity(0.92))
          )
        }
        .padding(.horizontal, 24)

        Text(String(localized: "\(viewModel.memberIds.count) members selected"))
          .font(.geistFootnote)
          .foregroundColor(.ecliptixSecondaryText)

        Spacer()

        Button {
          Task {
            if let conversationId = await viewModel.createGroup() {
              onGroupCreated(conversationId)
            }
          }
        } label: {
          Group {
            if viewModel.isCreating {
              ProgressView()
                .tint(.white)
            } else {
              Text(String(localized: "Create Group"))
                .font(.geist(.semiBold, size: 16))
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 46)
          .foregroundColor(.ecliptixPrimaryButtonText)
          .background(
            LinearGradient(
              colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(!viewModel.canCreate || viewModel.isCreating)
        .opacity(viewModel.canCreate ? 1 : 0.5)
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
      }
    }
    .navigationTitle(String(localized: "Create Group"))
    .navigationBarTitleDisplayMode(.inline)
    .alert(
      String(localized: "Error"),
      isPresented: $viewModel.hasError
    ) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var groupAvatar: some View {
    ZStack {
      Circle()
        .fill(Color.ecliptixAccent.gradient)
        .frame(width: 80, height: 80)
      Text(groupInitial)
        .font(.geist(.semiBold, size: 32))
        .foregroundStyle(.white)
    }
  }

  private var groupInitial: String {
    let trimmed = viewModel.groupName.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return "G" }
    return String(trimmed.prefix(1)).uppercased()
  }
}
