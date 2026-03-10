// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct OutboxDiagnosticsView: View {

  @Bindable var viewModel: OutboxDiagnosticsViewModel

  var body: some View {
    List {
      summarySection
      entriesSection
    }
    .navigationTitle("Outbox Diagnostics")
    .overlay {
      if viewModel.isLoading && viewModel.entries.isEmpty {
        ProgressView()
      }
    }
    .refreshable {
      await viewModel.refresh()
    }
    .alert(String(localized: "Diagnostics Error"), isPresented: $viewModel.hasError) {
      Button(String(localized: "OK")) {}
    } message: {
      Text(viewModel.errorMessage)
    }
    .task {
      await viewModel.load()
    }
    .onDisappear {
      viewModel.stopObserving()
    }
  }

  private var summarySection: some View {
    Section("Summary") {
      if let activeAccountId = viewModel.activeAccountId {
        LabeledContent("Account") {
          Text(activeAccountId.uuidString)
            .font(.geistCaption)
            .multilineTextAlignment(.trailing)
        }
      }
      LabeledContent("Quarantined Entries") {
        Text("\(viewModel.quarantinedCount)")
      }
    }
  }

  private var entriesSection: some View {
    Section("Entries") {
      if viewModel.entries.isEmpty {
        Text("No quarantined outbox entries")
          .foregroundStyle(.secondary)
      } else {
        ForEach(viewModel.entries) { entry in
          VStack(alignment: .leading, spacing: 8) {
            HStack {
              Text("#\(entry.id)")
                .font(.geist(.semiBold, size: 15))
              Spacer()
              Text(entry.payloadType)
                .font(.geistCaption)
                .foregroundStyle(.secondary)
            }

            LabeledContent("Retries") {
              Text("\(entry.retryCount)")
            }
            LabeledContent("Payload") {
              Text(ByteCountFormatter.string(fromByteCount: Int64(entry.payloadSizeBytes), countStyle: .file))
            }
            LabeledContent("Conversation") {
              Text(shortenedHex(entry.conversationIdHex))
                .font(.geistCaption)
                .multilineTextAlignment(.trailing)
            }
            LabeledContent("Created") {
              Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
            }
            if let lastAttemptAt = entry.lastAttemptAt {
              LabeledContent("Last Attempt") {
                Text(lastAttemptAt.formatted(date: .abbreviated, time: .shortened))
              }
            }
          }
          .padding(.vertical, 4)
        }
      }
    }
  }

  private func shortenedHex(_ value: String) -> String {
    guard value.count > 16 else { return value }
    let prefix = value.prefix(8)
    let suffix = value.suffix(8)
    return "\(prefix)...\(suffix)"
  }
}
