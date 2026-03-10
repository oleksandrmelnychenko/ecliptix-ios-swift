// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct SignInView: View {

  @State private var viewModel: SignInViewModel
  private let onBack: () -> Void

  init(
    viewModel: SignInViewModel,
    onBack: @escaping () -> Void = {}
  ) {
    _viewModel = State(wrappedValue: viewModel)
    self.onBack = onBack
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
    .navigationBarBackButtonHidden(viewModel.isSigningIn || viewModel.isAutoRedirecting)
    .onAppear { viewModel.onAppear() }
    .onDisappear { viewModel.onDisappear() }
  }

  private var mainContent: some View {
    @Bindable var vm = viewModel
    return ScrollView {
      VStack(spacing: 24) {
        HStack {
          Button(action: onBack) {
            HStack(spacing: 6) {
              Image(systemName: "chevron.left")
                .font(.geist(.semiBold, size: 14))
              Text(String(localized: "Back"))
                .font(.geist(.medium, size: 15))
            }
            .foregroundColor(.ecliptixPrimaryText)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(String(localized: "Back")))
          .accessibilityHint(Text(String(localized: "Return to previous screen")))
          Spacer()
        }
        Spacer().frame(height: 32)
        headerSection
        phoneInputSection
        passwordInputSection
        serverErrorBanner
        signInButton
        helpSection
        Spacer()
      }
      .padding(.horizontal, 24)
      .animation(.ecliptixSnappy, value: viewModel.hasServerError)
    }
    .disabled(viewModel.isSigningIn)
  }

  private var headerSection: some View {
    VStack(spacing: 12) {
      Text("Sign In")
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixPrimaryText)
      Text("Enter your mobile number and password to continue")
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)
        .multilineTextAlignment(.center)
    }
  }

  private var phoneInputSection: some View {
    @Bindable var vm = viewModel
    return VStack(spacing: 16) {
      countryPickerButton
      HintedTextField(
        placeholder: "Mobile Number",
        text: $vm.mobileNumber,
        error: viewModel.phoneValidationError,
        isDisabled: viewModel.isSigningIn,
        prefix: viewModel.selectedCountry.dialCode,
        keyboardType: .phonePad
      )
    }
  }

  private var countryPickerButton: some View {
    @Bindable var vm = viewModel
    return Button(action: { viewModel.showCountryPicker = true }) {
      HStack {
        Text(viewModel.selectedCountry.flag).font(.geist(.bold, size: 28))
        Text(viewModel.selectedCountry.name).font(.geistBody).foregroundColor(.ecliptixPrimaryText)
        Spacer()
        Image(systemName: "chevron.down").font(.geistFootnote)
          .foregroundColor(.ecliptixSecondaryText)
          .accessibilityHidden(true)
      }
      .ecliptixInput()
    }
    .disabled(viewModel.isSigningIn)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text("\(viewModel.selectedCountry.name), select country"))
    .sheet(isPresented: $vm.showCountryPicker) {
      CountryPickerView(selectedCountry: $vm.selectedCountry)
    }
  }

  private var passwordInputSection: some View {
    @Bindable var vm = viewModel
    return HintedTextField(
      placeholder: "Password",
      text: $vm.secureKey,
      error: viewModel.secureKeyError,
      isSecure: true,
      isDisabled: viewModel.isSigningIn,
      textContentType: .password
    )
  }

  private var signInButton: some View {
    Button(action: {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      Task { await viewModel.signIn() }
    }) {
      HStack {
        if viewModel.isSigningIn {
          ProgressView().progressViewStyle(
            CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText)
          )
          .scaleEffect(0.9)
        } else {
          Text("Continue").font(.geist(.semiBold, size: 17))
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.vertical, 15)
      .foregroundColor(.ecliptixPrimaryButtonText)
      .background(viewModel.isFormValid ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .animation(.ecliptixSnappy, value: viewModel.isFormValid)
    .disabled(!viewModel.isFormValid || viewModel.isSigningIn)
    .accessibilityLabel(viewModel.isSigningIn ? Text("Signing in") : Text("Continue"))
  }

  private var helpSection: some View {
    VStack(spacing: 12) {
      Button(action: { viewModel.accountRecovery() }) {
        Text("Forgot Secure Key?")
          .font(.geist(.medium, size: 15))
          .foregroundColor(.ecliptixAccent)
      }
      .disabled(viewModel.isSigningIn)
    }
  }

  private var serverErrorBanner: some View {
    ServerErrorBanner(message: viewModel.userFacingServerError)
  }

  private var autoRedirectOverlay: some View {
    VStack(spacing: 24) {
      Image(systemName: "exclamationmark.triangle.fill").font(.geistLargeTitle).foregroundColor(
        .ecliptixWarning
      )
      .accessibilityHidden(true)
      VStack(spacing: 8) {
        Text(viewModel.autoRedirectTitle).font(.geist(.bold, size: 28)).foregroundColor(
          .ecliptixPrimaryText
        )
        .multilineTextAlignment(.center)
        Text(viewModel.autoRedirectSubtitle).font(.geistSubheadline).foregroundColor(
          .ecliptixSecondaryText
        )
        .multilineTextAlignment(.center)
      }
      if viewModel.autoRedirectCountdown > 0 {
        Text("Redirecting in \(viewModel.autoRedirectCountdown)s...")
          .font(.geistSubheadline)
          .foregroundColor(.ecliptixSecondaryText)
          .padding(.top, 2)
      }
    }
    .padding(.horizontal, 32)
  }
}
