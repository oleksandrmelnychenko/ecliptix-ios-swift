import PhotosUI
// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct CompleteProfileView: View {

  @State private var viewModel: CompleteProfileViewModel
  @State private var selectedPhotoItem: PhotosPickerItem?
  init(viewModel: CompleteProfileViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    @Bindable var vm = viewModel
    ZStack {
      EcliptixScreenBackground()
      mainContent
    }
    .navigationBarBackButtonHidden(
      viewModel.isCompletingProfile || viewModel.currentStep == .personalize
    )
    .animation(.ecliptixSmooth, value: viewModel.currentStep)
    .photosPicker(
      isPresented: $vm.showImagePicker,
      selection: $selectedPhotoItem,
      matching: .images,
      preferredItemEncoding: .automatic
    )
    .onChange(of: selectedPhotoItem) { _, item in
      guard let item else { return }
      Task {
        if let imageData = try? await item.loadTransferable(type: Data.self) {
          await MainActor.run {
            viewModel.selectedAvatarData = imageData
          }
        }
      }
    }
  }

  private var mainContent: some View {
    ScrollView {
      VStack(spacing: 24) {
        Spacer()
          .frame(height: 32)
        headerSection
        stepContent
        ServerErrorBanner(message: viewModel.userFacingError)
        actionButton
        if viewModel.showSkipButton {
          skipButton
        }
        if viewModel.currentStep == .personalize && !viewModel.isBusy {
          backButton
        }
        Spacer()
      }
      .padding(.horizontal, 24)
      .animation(.ecliptixSnappy, value: viewModel.hasError)
    }
    .disabled(viewModel.isCompletingProfile)
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

  @ViewBuilder
  private var stepContent: some View {
    switch viewModel.currentStep {
    case .username:
      profileNameInputSection
        .transition(
          .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
          ))
    case .personalize:
      VStack(spacing: 24) {
        avatarSection
        displayNameInputSection
      }
      .transition(
        .asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          removal: .move(edge: .trailing).combined(with: .opacity)
        ))
    }
  }

  private var profileNameInputSection: some View {
    @Bindable var vm = viewModel
    return VStack(alignment: .leading, spacing: 4) {
      HintedTextField(
        placeholder: "username",
        text: $vm.profileName,
        hint: profileNameHint,
        error: viewModel.profileNameValidationError,
        isDisabled: viewModel.isCompletingProfile,
        prefix: "@",
        autocapitalization: .never,
        disableAutocorrection: true
      )
      if viewModel.isCheckingAvailability {
        HStack(spacing: 6) {
          ProgressView()
            .scaleEffect(0.7)
          Text("Checking availability...")
            .font(.geistCaption)
            .foregroundColor(.ecliptixSecondaryText)
        }
        .transition(.opacity)
      } else if viewModel.isProfileNameAvailable && !viewModel.profileName.isEmpty
        && viewModel.profileNameValidationError.isEmpty
      {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .font(.geistCaption)
            .foregroundColor(.ecliptixAccent)
          Text("Available")
            .font(.geistCaption)
            .foregroundColor(.ecliptixAccent)
        }
        .transition(.opacity)
      }
    }
    .animation(.ecliptixSnappy, value: viewModel.isCheckingAvailability)
    .animation(.ecliptixSnappy, value: viewModel.isProfileNameAvailable)
  }

  private var profileNameHint: String {
    "3-30 characters, letters, numbers, and underscore only"
  }

  private var avatarSection: some View {
    return VStack(spacing: 16) {
      ZStack {
        Circle()
          .fill(Color.ecliptixSurface)
          .frame(width: 100, height: 100)
          .overlay(
            Circle()
              .stroke(Color.ecliptixStroke, lineWidth: 1)
          )
        if let avatarData = viewModel.selectedAvatarData,
          let uiImage = UIImage(data: avatarData)
        {
          Image(uiImage: uiImage)
            .resizable()
            .scaledToFill()
            .frame(width: 100, height: 100)
            .clipShape(Circle())
        } else {
          Image(systemName: "person.fill")
            .font(.geistLargeTitle)
            .foregroundColor(.ecliptixSecondaryText)
        }
        Circle()
          .fill(Color.ecliptixPrimaryButton)
          .frame(width: 32, height: 32)
          .overlay(
            Image(systemName: "camera.fill")
              .font(.geistFootnote)
              .foregroundColor(.ecliptixPrimaryButtonText)
          )
          .offset(x: 35, y: 35)
      }
      .onTapGesture {
        viewModel.showImagePicker = true
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel(Text("Profile photo"))
      .accessibilityHint(Text("Tap to change"))
      Text("Add Photo")
        .font(.geistFootnote)
        .foregroundColor(.ecliptixAccent)
    }
  }

  private var displayNameInputSection: some View {
    @Bindable var vm = viewModel
    return HintedTextField(
      placeholder: "John Doe",
      text: $vm.displayName,
      hint: "Optional. Your public name (can be changed later)",
      error: viewModel.displayNameValidationError,
      isDisabled: viewModel.isCompletingProfile
    )
  }

  private var actionButton: some View {
    Button(action: {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
      switch viewModel.currentStep {
      case .username:
        viewModel.proceedToPersonalize()
      case .personalize:
        Task {
          await viewModel.completeProfile()
        }
      }
    }) {
      HStack {
        if viewModel.isCompletingProfile {
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
      .background(viewModel.isFormValid ? Color.ecliptixPrimaryButton : Color.ecliptixDisabled)
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .animation(.ecliptixSnappy, value: viewModel.isFormValid)
    .disabled(!viewModel.isFormValid || viewModel.isCompletingProfile)
    .accessibilityLabel(Text(viewModel.buttonText))
  }

  private var skipButton: some View {
    Button(action: {
      Task {
        await viewModel.skipProfile()
      }
    }) {
      Text("Skip for now")
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSubtleButtonText)
        .frame(minHeight: 44)
    }
    .buttonStyle(.plain)
    .disabled(viewModel.isCompletingProfile)
  }

  private var backButton: some View {
    Button(action: { viewModel.goBackToUsername() }) {
      Text("Back")
        .font(.geist(.medium, size: 15))
        .foregroundColor(.ecliptixSubtleButtonText)
    }
    .buttonStyle(.plain)
    .transition(.opacity)
  }
}

#Preview {
  NavigationStack {
    CompleteProfileView(
      viewModel: AppDependencies.shared.makeCompleteProfileViewModel(
        sessionId: "test-session",
        mobileNumber: "+1 234 567 8900"
      )
    )
  }
}
