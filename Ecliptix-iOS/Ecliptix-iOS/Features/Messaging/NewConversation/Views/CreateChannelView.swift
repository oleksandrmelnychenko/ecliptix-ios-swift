// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct CreateChannelView: View {

  @State var viewModel: CreateChannelViewModel
  var onChannelCreated: (Data) -> Void

  var body: some View {
    List {
      Section {
        HStack(spacing: 16) {
          ZStack {
            Circle()
              .fill(Color.ecliptixAccent.gradient)
              .frame(width: 60, height: 60)
            if viewModel.channelName.isEmpty {
              Image(systemName: "megaphone.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            } else {
              Text(viewModel.channelName.prefix(1).uppercased())
                .font(.geist(.semiBold, size: 24))
                .foregroundStyle(.white)
            }
          }

          VStack(spacing: 8) {
            TextField(String(localized: "Channel Name"), text: $viewModel.channelName)
              .font(.geist(.medium, size: 16))
            TextField(String(localized: "Description (optional)"), text: $viewModel.channelDescription, axis: .vertical)
              .font(.geist(.regular, size: 14))
              .foregroundColor(.ecliptixSecondaryText)
              .lineLimit(1...3)
          }
        }
        .listRowBackground(Color.ecliptixSurface)
      }

      Section {
        Toggle(String(localized: "Public Channel"), isOn: $viewModel.isPublic)
          .font(.geist(.regular, size: 15))
          .tint(.ecliptixAccent)
          .listRowBackground(Color.ecliptixSurface)

        Toggle(String(localized: "Admin Signatures"), isOn: $viewModel.adminSignatures)
          .font(.geist(.regular, size: 15))
          .tint(.ecliptixAccent)
          .listRowBackground(Color.ecliptixSurface)
      } footer: {
        Text(String(localized: "Public channels can be found by anyone. Admin signatures show author name on each post."))
          .font(.geistCaption)
          .foregroundColor(.ecliptixTertiaryText)
      }

      Section {
        Button {
          Task {
            if let channelId = await viewModel.createChannel() {
              onChannelCreated(channelId)
            }
          }
        } label: {
          HStack {
            Spacer()
            if viewModel.isCreating {
              ProgressView().tint(.ecliptixPrimaryButtonText)
            } else {
              Text(String(localized: "Create Channel"))
                .font(.geist(.semiBold, size: 16))
            }
            Spacer()
          }
          .foregroundColor(.ecliptixPrimaryButtonText)
          .padding(.vertical, 4)
        }
        .disabled(!viewModel.canCreate || viewModel.isCreating)
        .listRowBackground(
          viewModel.canCreate
            ? LinearGradient(
                colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
                startPoint: .leading, endPoint: .trailing
              )
            : LinearGradient(
                colors: [Color.ecliptixDisabled, Color.ecliptixDisabled],
                startPoint: .leading, endPoint: .trailing
              )
        )
      }
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(EcliptixScreenBackground())
    .navigationTitle(String(localized: "New Channel"))
    .navigationBarTitleDisplayMode(.inline)
    .alert(String(localized: "Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }
}
