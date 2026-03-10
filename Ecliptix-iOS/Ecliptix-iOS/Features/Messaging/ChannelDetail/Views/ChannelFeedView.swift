// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct ChannelFeedView: View {

  @State var viewModel: ChannelFeedViewModel
  var onNavigate: (MessagesNavigationDestination) -> Void

  var body: some View {
    ZStack {
      EcliptixScreenBackground()

      VStack(spacing: 0) {
        if viewModel.isLoading && viewModel.posts.isEmpty {
          Spacer()
          ProgressView().tint(.ecliptixAccent)
          Spacer()
        } else if viewModel.posts.isEmpty {
          Spacer()
          emptyState
          Spacer()
        } else {
          postList
        }

        if viewModel.isAdmin {
          composeBar
        }
      }
    }
    .navigationTitle(viewModel.channelTitle)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          onNavigate(.channelInfo(channelId: viewModel.channelId))
        } label: {
          Image(systemName: "info.circle")
            .foregroundColor(.ecliptixAccent)
        }
      }
    }
    .task {
      await viewModel.loadChannel()
      await viewModel.loadPosts()
    }
    .alert(String(localized: "Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK"), role: .cancel) {}
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private var postList: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(viewModel.posts) { post in
          ChannelPostCell(post: post, isAdmin: viewModel.isAdmin) {
            Task { await viewModel.deletePost(post.id) }
          }
          .padding(.horizontal, 16)
          .padding(.vertical, 8)

          Divider()
            .foregroundColor(.ecliptixMutedStroke)
            .padding(.horizontal, 16)
        }

        if viewModel.hasMorePosts {
          ProgressView()
            .tint(.ecliptixAccent)
            .padding()
            .task { await viewModel.loadMorePosts() }
        }
      }
    }
    .refreshable { await viewModel.loadPosts() }
  }

  private var composeBar: some View {
    HStack(spacing: 12) {
      TextField(String(localized: "Write a post…"), text: $viewModel.inputText, axis: .vertical)
        .font(.geist(.regular, size: 15))
        .lineLimit(1...5)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ecliptixSurface)
        .clipShape(RoundedRectangle(cornerRadius: 18))

      Button {
        Task { await viewModel.sendPost() }
      } label: {
        Image(systemName: "paperplane.fill")
          .font(.system(size: 20))
          .foregroundColor(
            viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? .ecliptixTertiaryText : .ecliptixAccent
          )
      }
      .disabled(
        viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || viewModel.isSending
      )
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .background(Color.ecliptixBackground)
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Image(systemName: "megaphone")
        .font(.system(size: 40))
        .foregroundColor(.ecliptixTertiaryText)
      Text(String(localized: "No posts yet"))
        .font(.geist(.medium, size: 16))
        .foregroundColor(.ecliptixSecondaryText)
    }
  }
}
