// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct WelcomeBackView: View {

  let viewModel: WelcomeBackViewModel
  var body: some View {
    ZStack {
      LinearGradient(
        gradient: Gradient(colors: [Color.ecliptixBackground, Color.ecliptixBackgroundSecondary]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
      .ignoresSafeArea()
      VStack(spacing: 40) {
        Spacer()
        VStack(spacing: 16) {
          Image("EcliptixLogo")
            .resizable()
            .scaledToFit()
            .frame(width: 80, height: 80)
            .accessibilityHidden(true)
          Text(String(localized: "Welcome Back"))
            .font(.geist(.bold, size: 34))
            .foregroundColor(.ecliptixPrimaryText)
          Text(
            String(
              localized:
                "You have an incomplete registration. Would you like to continue setting up your account?"
            )
          )
          .font(.geistSubheadline)
          .foregroundColor(.ecliptixSecondaryText)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 16)
        }
        Spacer()
        if viewModel.hasError {
          Text(viewModel.errorMessage)
            .font(.geistFootnote)
            .foregroundColor(.ecliptixDanger)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        VStack(spacing: 16) {
          Button(action: { viewModel.continueToSetup() }) {
            Text(String(localized: "Continue to Setup"))
              .font(.geist(.semiBold, size: 17))
              .frame(maxWidth: .infinity, minHeight: 44)
              .padding(.vertical, 16)
              .foregroundColor(.ecliptixPrimaryButtonText)
              .background(
                LinearGradient(
                  colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
                  startPoint: .leading,
                  endPoint: .trailing
                )
              )
              .clipShape(RoundedRectangle(cornerRadius: 12))
          }
          .disabled(viewModel.isBusy)
          Button(action: { viewModel.continueLater() }) {
            Text(String(localized: "Continue Later"))
              .font(.geist(.semiBold, size: 17))
              .frame(maxWidth: .infinity, minHeight: 44)
              .padding(.vertical, 16)
              .foregroundColor(.ecliptixSecondaryButtonText)
              .background(Color.ecliptixSecondaryButton)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .overlay(
                RoundedRectangle(cornerRadius: 12).stroke(Color.ecliptixMutedStroke, lineWidth: 1))
          }
          .disabled(viewModel.isBusy)
        }
        .padding(.horizontal, 32)
        Spacer().frame(height: 60)
      }
    }
  }
}
