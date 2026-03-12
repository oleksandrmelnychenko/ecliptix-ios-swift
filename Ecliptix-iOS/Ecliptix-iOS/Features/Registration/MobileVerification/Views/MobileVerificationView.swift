// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct MobileVerificationView: View {

  @State private var viewModel: MobileVerificationViewModel
  @Environment(\.openURL) private var openURL
  private let onBack: (() -> Void)?

  init(viewModel: MobileVerificationViewModel, onBack: (() -> Void)? = nil) {
    _viewModel = State(wrappedValue: viewModel)
    self.onBack = onBack
  }

  var body: some View {
    ZStack {
      EcliptixScreenBackground()
      mainContent
    }
    .navigationTitle(viewModel.title)
    .navigationBarTitleDisplayMode(.inline)
    .navigationBarBackButtonHidden(onBack != nil || viewModel.isSendingCode)
    .ignoresSafeArea(.keyboard, edges: .bottom)
    .toolbar {
      if viewModel.flowContext == .registration, let onBack, !viewModel.isSendingCode {
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
    .onAppear { viewModel.onAppear() }
  }

  private var mainContent: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer()
          .frame(height: 32)
        titleSection
        phoneInputSection
        serverErrorSection
        continueButton
        if viewModel.flowContext == .registration {
          termsSection
        }
        Spacer()
      }
      .padding(.horizontal, 24)
    }
    .disabled(viewModel.isSendingCode)
  }

  private var titleSection: some View {
    VStack(spacing: 12) {
      Text(viewModel.title)
        .font(.geistLargeTitle)
        .foregroundColor(.ecliptixPrimaryText)
      Text(viewModel.subtitle)
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
        hint: viewModel.infoMessage,
        error: viewModel.phoneValidationError,
        isDisabled: viewModel.isSendingCode,
        prefix: viewModel.selectedCountry.dialCode,
        keyboardType: .phonePad
      )
    }
  }

  private var countryPickerButton: some View {
    @Bindable var vm = viewModel
    return Button(action: {
      viewModel.showCountryPicker = true
    }) {
      HStack {
        Text(viewModel.selectedCountry.flag)
          .font(.title3)
        Text(viewModel.selectedCountry.name)
          .font(.geistBody)
          .foregroundColor(.ecliptixPrimaryText)
        Spacer()
        Image(systemName: "chevron.down")
          .font(.geist(.semiBold, size: 13))
          .foregroundColor(.ecliptixSecondaryText)
      }
      .ecliptixInput()
    }
    .disabled(viewModel.isSendingCode)
    .sheet(isPresented: $vm.showCountryPicker) {
      CountryPickerView(selectedCountry: $vm.selectedCountry)
    }
  }

  private var continueButton: some View {
    Button(action: {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      Task {
        await viewModel.sendVerificationCode()
      }
    }) {
      HStack {
        if viewModel.isSendingCode {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText))
            .scaleEffect(0.9)
        } else {
          Text(viewModel.buttonText)
            .font(.geist(.semiBold, size: 17))
        }
      }
      .frame(maxWidth: .infinity, minHeight: 44)
      .padding(.vertical, 15)
      .foregroundColor(.ecliptixPrimaryButtonText)
      .background(viewModel.isFormValid ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .animation(.ecliptixSnappy, value: viewModel.isFormValid)
    .disabled(!viewModel.isFormValid || viewModel.isSendingCode)
    .accessibilityLabel(viewModel.isSendingCode ? Text("Sending code") : Text(viewModel.buttonText))
  }

  private var serverErrorSection: some View {
    VStack(spacing: 0) {
      if !viewModel.userFacingError.isEmpty {
        ServerErrorBanner(message: viewModel.userFacingError)
      }
    }
    .frame(
      maxWidth: .infinity,
      minHeight: viewModel.flowContext == .registration ? 48 : 0,
      alignment: .top
    )
    .animation(.ecliptixSnappy, value: viewModel.userFacingError)
  }

  private var termsSection: some View {
    @Bindable var vm = viewModel
    return VStack(spacing: 12) {
      Toggle(isOn: $vm.hasAgreedToTerms) {
        Text("I agree to the Terms of Service and Privacy Policy")
          .font(.geistFootnote)
          .foregroundColor(.ecliptixPrimaryText)
      }
      .toggleStyle(CheckboxToggleStyle())
      .disabled(viewModel.isSendingCode)
      if !viewModel.termsValidationError.isEmpty {
        HStack {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundColor(.ecliptixDanger)
          Text(viewModel.termsValidationError)
            .font(.geistFootnote)
            .foregroundColor(.ecliptixDanger)
          Spacer()
        }
      }
      HStack(spacing: 16) {
        Button("Terms of Service") {
          openLegalURL(AppConstants.SystemSettings.termsOfServiceURL)
        }
        .font(.geistFootnote)
        .foregroundColor(.ecliptixAccent)
        Text("•")
          .foregroundColor(.ecliptixSecondaryText)
        Button("Privacy Policy") {
          openLegalURL(AppConstants.SystemSettings.privacyPolicyURL)
        }
        .font(.geistFootnote)
        .foregroundColor(.ecliptixAccent)
      }
    }
    .padding(.top, 8)
  }

  private func openLegalURL(_ rawURL: String) {
    guard let url = URL(string: rawURL) else { return }
    openURL(url)
  }
}

#Preview("Registration") {
  NavigationStack {
    MobileVerificationView(
      viewModel: AppDependencies.shared.makeMobileVerificationViewModel(
        flowContext: .registration
      )
    )
  }
}

#Preview("Sign In") {
  NavigationStack {
    MobileVerificationView(
      viewModel: AppDependencies.shared.makeMobileVerificationViewModel(
        flowContext: .signIn
      )
    )
  }
}

#Preview("Recovery") {
  NavigationStack {
    MobileVerificationView(
      viewModel: AppDependencies.shared.makeMobileVerificationViewModel(
        flowContext: .secureKeyRecovery
      )
    )
  }
}
