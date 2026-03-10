// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct SecureKeyConfirmationView: View {

  @State private var viewModel: SecureKeyConfirmationViewModel
  var onBack: (() -> Void)?

  init(viewModel: SecureKeyConfirmationViewModel, onBack: (() -> Void)? = nil) {
    _viewModel = State(wrappedValue: viewModel)
    self.onBack = onBack
  }

  var body: some View {
    @Bindable var vm = viewModel
    ZStack {
      EcliptixScreenBackground()
      ScrollView {
        VStack(spacing: 24) {
          Text(viewModel.title)
            .font(.geistLargeTitle)
            .foregroundColor(.ecliptixPrimaryText)
          Text(viewModel.description)
            .font(.geistSubheadline)
            .foregroundColor(.ecliptixSecondaryText)
            .multilineTextAlignment(.center)
          HintedTextField(
            placeholder: "Secure Key",
            text: $vm.secureKey,
            error: viewModel.secureKeyError,
            isSecure: true,
            textContentType: .newPassword
          )
          HintedTextField(
            placeholder: "Confirm Secure Key",
            text: $vm.verifySecureKey,
            error: viewModel.verifySecureKeyError,
            isSecure: true,
            textContentType: .newPassword
          )
          VStack(alignment: .leading, spacing: 6) {
            Text(
              String(
                format: String(localized: "Strength: %@"),
                viewModel.currentSecureKeyStrength.localizedName)
            )
            .font(.geist(.semiBold, size: 13))
            .foregroundColor(.ecliptixSecondaryText)
            ForEach(viewModel.validationTips) { item in
              HStack(spacing: 8) {
                Image(systemName: item.isSatisfied ? "checkmark.circle.fill" : "circle")
                  .foregroundColor(item.isSatisfied ? .ecliptixAccent : .ecliptixSecondaryText)
                  .accessibilityHidden(true)
                Text(item.description)
                  .font(.geistCaption)
                  .foregroundColor(.ecliptixSecondaryText)
              }
              .accessibilityElement(children: .combine)
              .accessibilityLabel(
                Text("\(item.description), \(item.isSatisfied ? "met" : "not met")"))
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          if !viewModel.recommendations.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
              ForEach(viewModel.recommendations, id: \.self) { recommendation in
                HStack(spacing: 8) {
                  Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.ecliptixWarning)
                    .font(.geistCaption2)
                    .accessibilityHidden(true)
                  Text(recommendation)
                    .font(.geistCaption)
                    .foregroundColor(.ecliptixSecondaryText)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          if viewModel.hasServerError {
            Text(viewModel.serverError)
              .font(.geistFootnote)
              .foregroundColor(.ecliptixDanger)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          Button(action: {
            UIApplication.shared.sendAction(
              #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            Task { await viewModel.submit() }
          }) {
            HStack {
              if viewModel.isBusy {
                ProgressView()
                  .progressViewStyle(CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText))
              } else {
                Text(viewModel.buttonText)
                  .font(.geist(.semiBold, size: 17))
              }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundColor(.ecliptixPrimaryButtonText)
            .background(viewModel.canSubmit ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
            .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .animation(.ecliptixSnappy, value: viewModel.canSubmit)
          .disabled(!viewModel.canSubmit || viewModel.isBusy)
          .accessibilityLabel(Text("Submit secure key"))
        }
        .padding(24)
      }
    }
    .navigationBarBackButtonHidden(onBack != nil || viewModel.isBusy)
    .toolbar {
      if let onBack, !viewModel.isBusy {
        ToolbarItem(placement: .navigationBarLeading) {
          Button(action: onBack) {
            HStack(spacing: 4) {
              Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
              Text("Back")
                .font(.geist(.medium, size: 16))
            }
            .foregroundColor(.ecliptixAccent)
          }
        }
      }
    }
  }
}

#Preview {
  NavigationStack {
    SecureKeyConfirmationView(
      viewModel: AppDependencies.shared.makeSecureKeyConfirmationViewModel(
        flowContext: .registration
      )
    )
  }
}
