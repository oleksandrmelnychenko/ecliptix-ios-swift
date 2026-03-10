// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct OtpVerificationView: View {

  @State private var viewModel: OtpVerificationViewModel
  @FocusState private var focusedField: Int?
  @FocusState private var isOtpInputFocused: Bool
  @Environment(\.dismiss) private var dismiss
  init(viewModel: OtpVerificationViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      EcliptixScreenBackground()
      if viewModel.isAutoRedirecting {
        autoRedirectOverlay
      } else {
        mainContent
      }
    }
    .navigationBarBackButtonHidden(viewModel.isBusy || viewModel.isAutoRedirecting)
    .onAppear {
      viewModel.startCountdown()
      focusedField = 0
      isOtpInputFocused = true
    }
    .onDisappear {
      viewModel.onDisappear()
    }
  }

  private var mainContent: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer()
          .frame(height: 32)
        headerSection
        otpInputSection
        ServerErrorBanner(message: viewModel.userFacingError)
          .animation(.ecliptixSnappy, value: viewModel.hasError)
        statusSection
        resendSection
        verifyButton
        Spacer()
      }
      .padding(.horizontal, 24)
    }
    .disabled(viewModel.isBusy)
  }

  private var headerSection: some View {
    VStack(spacing: 12) {
      Text("Verify Code")
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixPrimaryText)
      Text("Enter the 6-digit code sent to")
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)
      Text(viewModel.mobileNumber)
        .font(.geist(.semiBold, size: 15))
        .foregroundColor(.ecliptixPrimaryText)
      Button(action: {
        dismiss()
      }) {
        Text("Change Number")
          .font(.geistFootnote)
          .foregroundColor(.ecliptixAccent)
      }
      .disabled(viewModel.isBusy)
    }
  }

  private var otpInputSection: some View {
    @Bindable var vm = viewModel
    return VStack(spacing: 16) {
      HStack(spacing: 12) {
        ForEach(0..<6, id: \.self) { index in
          OtpDigitField(
            digit: binding(for: index),
            isFocused: focusedField == index,
            index: index,
            totalDigits: AppConstants.Otp.defaultOtpCodeLength,
            onTap: {
              focusedField = index
              isOtpInputFocused = true
            },
            onDigitEntered: {
              handleDigitEntered(at: index)
            },
            onBackspace: {
              handleBackspace(at: index)
            }
          )
        }
      }
      TextField("", text: $vm.verificationCode)
        .keyboardType(.numberPad)
        .opacity(0)
        .frame(width: 0, height: 0)
        .focused($isOtpInputFocused)
    }
  }

  private func binding(for index: Int) -> Binding<String> {
    Binding(
      get: {
        guard index < viewModel.otpDigits.count else { return "" }
        return viewModel.otpDigits[index]
      },
      set: { newValue in
        if index < viewModel.otpDigits.count {
          viewModel.otpDigits[index] = newValue
          updateVerificationCode()
        }
      }
    )
  }

  private func handleDigitEntered(at index: Int) {
    if index < 5 {
      focusedField = index + 1
    } else {
      focusedField = nil
      if viewModel.canVerify {
        Task {
          await viewModel.verifyOtp()
        }
      }
    }
  }

  private func handleBackspace(at index: Int) {
    if viewModel.otpDigits[index].isEmpty && index > 0 {
      focusedField = index - 1
    }
  }

  private func updateVerificationCode() {
    viewModel.verificationCode = viewModel.otpDigits.joined()
  }

  @ViewBuilder
  private var statusSection: some View {
    if viewModel.isBusy {
      HStack(spacing: 12) {
        ProgressView()
          .scaleEffect(0.9)
        Text("Verifying code...")
          .font(.geistSubheadline)
          .foregroundColor(.ecliptixSecondaryText)
      }
      .padding(.vertical, 12)
    } else if let status = countdownStatusMessage {
      HStack(spacing: 8) {
        Image(systemName: status.icon)
          .foregroundColor(status.color)
        Text(status.message)
          .font(.geistSubheadline)
          .foregroundColor(status.color)
      }
      .padding(.vertical, 12)
    }
  }

  private var countdownStatusMessage: (message: String, icon: String, color: Color)? {
    switch viewModel.countdownStatus {
    case .active(let remaining):
      return (
        "\(String(localized: "Code expires in")) \(formatDuration(remaining))", "clock.fill",
        .ecliptixSecondaryText
      )
    case .expired:
      return (
        String(localized: "Code expired - request a new one"), "exclamationmark.circle.fill",
        .ecliptixWarning
      )
    case .resendCooldown(let remaining):
      return (
        "\(String(localized: "Request new code in")) \(formatDuration(remaining))", "clock.fill",
        .ecliptixSecondaryText
      )
    case .failed:
      return (String(localized: "Verification failed"), "xmark.circle.fill", .ecliptixDanger)
    case .notFound:
      return (
        String(localized: "Session not found - please try again"), "exclamationmark.triangle.fill",
        .ecliptixWarning
      )
    case .maxAttemptsReached:
      return (
        String(localized: "Too many attempts - please try again later"),
        "exclamationmark.triangle.fill", .ecliptixDanger
      )
    case .sessionExpired:
      return (
        String(localized: "Session expired"), "clock.badge.exclamationmark.fill", .ecliptixWarning
      )
    case .serverUnavailable:
      return (
        String(localized: "Server unavailable - please try again"), "wifi.exclamationmark",
        .ecliptixDanger
      )
    }
  }

  private func formatDuration(_ totalSeconds: Int) -> String {
    let safeSeconds = max(0, totalSeconds)
    let minutes = safeSeconds / 60
    let seconds = safeSeconds % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private var resendSection: some View {
    VStack(spacing: 12) {
      if viewModel.isResending {
        HStack(spacing: 8) {
          ProgressView()
            .scaleEffect(0.8)
          Text("Sending new code...")
            .font(.geistFootnote)
            .foregroundColor(.ecliptixSecondaryText)
        }
      } else if viewModel.resendSucceeded {
        HStack(spacing: 8) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
          Text("Code sent!")
            .font(.geist(.semiBold, size: 15))
            .foregroundColor(.green)
        }
        .transition(.opacity)
      } else if viewModel.canResend {
        Button(action: {
          Task {
            await viewModel.resendOtp()
          }
        }) {
          Text("Resend Code")
            .font(.geist(.semiBold, size: 15))
            .foregroundColor(.ecliptixAccent)
        }
        .accessibilityLabel(Text("Resend verification code"))
      } else if viewModel.currentStatus == .expired {
        Text("Didn't receive code?")
          .font(.geistFootnote)
          .foregroundColor(.ecliptixSecondaryText)
      }
    }
    .animation(.easeInOut(duration: 0.25), value: viewModel.isResending)
    .animation(.easeInOut(duration: 0.25), value: viewModel.resendSucceeded)
    .animation(.easeInOut(duration: 0.25), value: viewModel.canResend)
  }

  private var verifyButton: some View {
    Button(action: {
      focusedField = nil
      isOtpInputFocused = false
      Task {
        await viewModel.verifyOtp()
      }
    }) {
      Text("Verify")
        .font(.geist(.semiBold, size: 17))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 15)
        .foregroundColor(.ecliptixPrimaryButtonText)
        .background(viewModel.canVerify ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .animation(.ecliptixSnappy, value: viewModel.canVerify)
    .disabled(!viewModel.canVerify || viewModel.isBusy)
    .accessibilityLabel(Text("Verify code"))
  }

  private var autoRedirectOverlay: some View {
    VStack(spacing: 24) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixWarning)
        .accessibilityHidden(true)
      VStack(spacing: 8) {
        Text(viewModel.autoRedirectTitle)
          .font(.geist(.bold, size: 28))
          .foregroundColor(.ecliptixPrimaryText)
          .multilineTextAlignment(.center)
        Text(viewModel.autoRedirectSubtitle)
          .font(.geistSubheadline)
          .foregroundColor(.ecliptixSecondaryText)
          .multilineTextAlignment(.center)
      }
      if viewModel.autoRedirectCountdown > 0 {
        Text(
          String(
            format: String(localized: "Redirecting in %ds..."), viewModel.autoRedirectCountdown)
        )
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)
        .padding(.top, 2)
      }
    }
    .padding(.horizontal, 32)
  }
}

#Preview {
  NavigationStack {
    OtpVerificationView(
      viewModel: AppDependencies.shared.makeOtpVerificationViewModel(
        sessionId: "test-session-id",
        mobileNumber: "+1 234 567 8900"
      )
    )
  }
}
