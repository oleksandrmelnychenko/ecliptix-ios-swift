// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct PinSetupView: View {

  @State private var viewModel: PinSetupViewModel
  @FocusState private var isInputFocused: Bool
  var onBack: (() -> Void)?

  init(viewModel: PinSetupViewModel, onBack: (() -> Void)? = nil) {
    _viewModel = State(wrappedValue: viewModel)
    self.onBack = onBack
  }

  var body: some View {
    ZStack {
      EcliptixScreenBackground()
      ScrollView {
        VStack(spacing: 24) {
          Spacer()
            .frame(height: 32)
          headerSection
          pinDotsSection
          errorSection
          actionButton
          backButton
          Spacer()
        }
        .padding(.horizontal, 24)
      }
      .disabled(viewModel.isBusy)
      hiddenInput
    }
    .onAppear { isInputFocused = true }
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .navigationBarBackButtonHidden(onBack != nil || viewModel.isBusy || viewModel.isConfirmStep)
    .toolbar {
      if let onBack, !viewModel.isBusy, !viewModel.isConfirmStep {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: onBack) {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
                .font(.geist(.semiBold, size: 16))
              Text("Back")
                .font(.geist(.medium, size: 16))
            }
            .foregroundColor(.ecliptixAccent)
          }
        }
      }
    }
    .animation(.ecliptixSmooth, value: viewModel.isConfirmStep)
  }

  private var headerSection: some View {
    VStack(spacing: 12) {
      HStack {
        Text(viewModel.stepBadgeText)
          .font(.geist(.semiBold, size: 12))
          .foregroundColor(.ecliptixAccent)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(
            Capsule().fill(Color.ecliptixAccent.opacity(0.12))
          )
        Spacer()
      }
      Text(viewModel.title)
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixPrimaryText)
      Text(viewModel.subtitle)
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)
        .multilineTextAlignment(.center)
    }
  }

  private var pinDotsSection: some View {
    let currentPin = viewModel.isConfirmStep ? viewModel.confirmPin : viewModel.pin
    return PinDotView(
      filledCount: currentPin.count,
      hasError: viewModel.hasPinError
    )
    .padding(.vertical, 24)
    .contentShape(Rectangle())
    .onTapGesture { isInputFocused = true }
  }

  @ViewBuilder
  private var errorSection: some View {
    VStack(spacing: 0) {
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
        .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 24, alignment: .top)
    .animation(.ecliptixSnappy, value: viewModel.hasPinError)
  }

  private var actionButton: some View {
    Button(action: {
      isInputFocused = false
      Task { await viewModel.proceed() }
    }) {
      HStack {
        if viewModel.isBusy {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText))
            .scaleEffect(0.9)
        } else {
          Text(viewModel.buttonText)
            .font(.geist(.semiBold, size: 17))
        }
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 15)
      .foregroundColor(.ecliptixPrimaryButtonText)
      .background(viewModel.canProceed ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .animation(.ecliptixSnappy, value: viewModel.canProceed)
    .disabled(!viewModel.canProceed || viewModel.isBusy)
    .accessibilityLabel(Text(viewModel.buttonText))
  }

  @ViewBuilder
  private var backButton: some View {
    if viewModel.isConfirmStep && !viewModel.isBusy {
      Button(action: { viewModel.goBack() }) {
        Text("Back")
          .font(.geist(.medium, size: 15))
          .foregroundColor(.ecliptixSubtleButtonText)
      }
      .buttonStyle(.plain)
      .transition(.opacity)
    }
  }

  private var hiddenInput: some View {
    TextField("", text: viewModel.isConfirmStep ? $viewModel.confirmPin : $viewModel.pin)
      .keyboardType(.numberPad)
      .textContentType(.none)
      .focused($isInputFocused)
      .frame(width: 1, height: 1)
      .opacity(0.01)
      .allowsHitTesting(false)
  }
}
