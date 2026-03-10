// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PinEntryView: View {

  @State private var viewModel: PinEntryViewModel
  @FocusState private var isInputFocused: Bool
  init(viewModel: PinEntryViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      EcliptixScreenBackground()
      VStack(spacing: 24) {
        Spacer(minLength: 60)
        headerSection
        pinDotsSection
        errorSection
        actionButton
        Spacer()
      }
      .padding(.horizontal, 24)
      .disabled(viewModel.isBusy)
      hiddenInput
    }
    .onAppear { isInputFocused = true }
    .navigationBarBackButtonHidden(true)
  }

  private var headerSection: some View {
    VStack(spacing: 12) {
      Text(
        viewModel.isLocked ? String(localized: "Account Locked") : String(localized: "Enter PIN")
      )
      .font(.geistLargeTitle)
      .foregroundColor(.ecliptixPrimaryText)
      Text(
        viewModel.isLocked
          ? String(localized: "Too many failed attempts. Please try again later.")
          : String(localized: "Enter your 4-digit PIN to continue")
      )
      .font(.geistSubheadline)
      .foregroundColor(.ecliptixSecondaryText)
      .multilineTextAlignment(.center)
    }
  }

  private var pinDotsSection: some View {
    PinDotView(
      filledCount: viewModel.pin.count,
      hasError: viewModel.hasPinError
    )
    .padding(.vertical, 24)
    .contentShape(Rectangle())
    .onTapGesture { isInputFocused = true }
    .opacity(viewModel.isLocked ? 0.4 : 1.0)
  }

  @ViewBuilder
  private var errorSection: some View {
    if viewModel.hasPinError {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.ecliptixDanger)
          .accessibilityHidden(true)
        Text(viewModel.pinError)
          .font(.geistFootnote)
          .foregroundColor(.ecliptixDanger)
      }
      .multilineTextAlignment(.center)
      .padding(.horizontal, 16)
      .transition(.opacity.combined(with: .move(edge: .top)))
    }
  }

  private var actionButton: some View {
    Button(action: {
      isInputFocused = false
      Task { await viewModel.verifyPin() }
    }) {
      HStack {
        if viewModel.isBusy {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText))
            .scaleEffect(0.9)
        } else {
          Text("Verify")
            .font(.geist(.semiBold, size: 17))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 15)
      .foregroundColor(.ecliptixPrimaryButtonText)
      .background(viewModel.canVerify ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .animation(.ecliptixSnappy, value: viewModel.canVerify)
    .disabled(!viewModel.canVerify || viewModel.isBusy)
    .accessibilityLabel(Text("Verify PIN"))
  }

  private var hiddenInput: some View {
    TextField("", text: $viewModel.pin)
      .keyboardType(.numberPad)
      .textContentType(.none)
      .focused($isInputFocused)
      .frame(width: 1, height: 1)
      .opacity(0.01)
      .allowsHitTesting(false)
      .disabled(viewModel.isLocked)
  }
}
