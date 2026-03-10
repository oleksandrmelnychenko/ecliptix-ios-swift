// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct CreatePostView: View {

  @State var viewModel: CreatePostViewModel
  @Environment(\.dismiss) private var dismiss
  @FocusState private var isTextFocused: Bool

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      VStack(spacing: 0) {
        HStack {
          Button(String(localized: "Cancel")) {
            dismiss()
          }
          .font(.geistBody)
          .foregroundStyle(Color.ecliptixSecondaryText)

          Spacer()

          Button {
            Task { await viewModel.submitPost() }
          } label: {
            Text(String(localized: "Post"))
              .font(.geist(.semiBold, size: 15))
              .foregroundStyle(.white)
              .padding(.horizontal, 20)
              .padding(.vertical, 8)
              .background(
                viewModel.canPost ? Color.ecliptixAccent : Color.ecliptixAccent.opacity(0.5)
              )
              .clipShape(Capsule())
          }
          .disabled(!viewModel.canPost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)

        Divider()
          .foregroundStyle(Color.ecliptixMutedStroke)

        if viewModel.mode == .reply, let authorName = viewModel.replyToAuthorName {
          HStack(spacing: 4) {
            Text(String(localized: "Replying to"))
              .font(.geistFootnote)
              .foregroundStyle(Color.ecliptixSecondaryText)
            Text("@\(authorName)")
              .font(.geistFootnote)
              .foregroundStyle(Color.ecliptixAccent)
          }
          .padding(.horizontal, 16)
          .padding(.top, 8)
        }

        ScrollView {
          TextEditor(text: $viewModel.textContent)
            .font(.geistBody)
            .foregroundStyle(Color.ecliptixPrimaryText)
            .scrollContentBackground(.hidden)
            .focused($isTextFocused)
            .frame(minHeight: 120)
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .overlay(alignment: .topLeading) {
              if viewModel.textContent.isEmpty {
                Text(placeholderText)
                  .font(.geistBody)
                  .foregroundStyle(Color.ecliptixTertiaryText)
                  .padding(.horizontal, 16)
                  .padding(.top, 16)
                  .allowsHitTesting(false)
              }
            }
        }

        Spacer()

        HStack {
          Spacer()

          characterCountView
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.ecliptixSurface)
      }

      if viewModel.isPosting {
        Color.black.opacity(0.3)
          .ignoresSafeArea()
        ProgressView()
          .tint(.white)
          .accessibilityLabel(String(localized: "Posting..."))
      }
    }
    .onAppear { isTextFocused = true }
    .alert(String(localized: "Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var placeholderText: String {
    switch viewModel.mode {
    case .original: String(localized: "What's happening?")
    case .reply: String(localized: "Post your reply")
    case .quote: String(localized: "Add a comment")
    }
  }

  @ViewBuilder
  private var characterCountView: some View {
    let ratio = viewModel.characterCountRatio
    let color: Color =
      ratio > 1.0 ? .ecliptixDanger : ratio > 0.9 ? .orange : .ecliptixSecondaryText

    HStack(spacing: 8) {
      if viewModel.characterCount > 0 {
        Text("\(viewModel.maxCharacters - viewModel.characterCount)")
          .font(.geistCaption)
          .foregroundStyle(color)
      }

      Circle()
        .trim(from: 0, to: min(ratio, 1.0))
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .frame(width: 20, height: 20)
        .background {
          Circle()
            .stroke(Color.ecliptixMutedStroke, lineWidth: 2)
        }
    }
  }
}
