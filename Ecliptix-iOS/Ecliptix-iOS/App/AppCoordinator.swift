// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

protocol Resettable: AnyObject {

  @MainActor func resetState()
}

@Observable @MainActor
final class AppCoordinator {

  var currentScreen: AppScreen = .splash
  var navigationPath: [NavigationDestination] = []
  var isStartupInProgress: Bool = false
  let dependencies: any AppCoordinatorDependencyProviding
  private(set) var accountSettingsViewModel: AccountSettingsViewModel
  private var viewModelCache: [String: AnyObject] = [:]

  init(dependencies: any AppCoordinatorDependencyProviding) {
    self.dependencies = dependencies
    self.accountSettingsViewModel = dependencies.makeAccountSettingsViewModel()
  }

  func cachedViewModel<T: AnyObject>(key: String, factory: () -> T) -> T {
    if let cached = viewModelCache[key] as? T {
      if let resettable = cached as? Resettable {
        resettable.resetState()
      }
      return cached
    }

    let vm = factory()
    viewModelCache[key] = vm
    return vm
  }

  func clearViewModelCache() {
    viewModelCache.removeAll()
  }

  func startup(settings: DefaultSystemSettings) async {
    guard !isStartupInProgress else { return }
    isStartupInProgress = true
    defer { isStartupInProgress = false }

    currentScreen = .splash
    let decision = dependencies.appFlowResolver.resolveStartupDecision(
      initializationResult: await dependencies.applicationInitializer.initialize(
        defaultCulture: settings.culture
      ),
      applicationState: dependencies.applicationStateManager.currentState,
      settings: dependencies.currentAppSettings(),
      storedIdentity: dependencies.resolveStoredIdentity()
    )
    applyStartupDecision(decision)
  }
}

enum AppScreen: Equatable {
  case splash
  case welcome
  case welcomeBack
  case signIn
  case registration
  case main
  case error(message: String)
}

enum NavigationDestination: Hashable {
  case mobileVerification(context: AuthenticationFlowContext)
  case otpVerification(sessionId: String, mobileNumber: String, context: AuthenticationFlowContext)
  case secureKeyConfirmation(
    sessionId: String, mobileNumber: String, context: AuthenticationFlowContext,
    membershipId: UUID?, membershipIdBytes: Data?)
  case pinSetup(sessionId: String, mobileNumber: String, context: AuthenticationFlowContext)
  case completeProfile(sessionId: String, mobileNumber: String)
  case pinEntry
  case signIn
}

@MainActor
struct RootView: View {

  @State private var coordinator = AppCoordinator(dependencies: AppDependencies.shared)
  @State private var hasStarted = false
  @State private var splashViewModel = SplashViewModel()
  var body: some View {
    RootViewBuilder.screenContent(coordinator: coordinator, splashViewModel: splashViewModel)
      .environment(coordinator)
      .task {
        guard !hasStarted else { return }
        hasStarted = true
        await coordinator.startup(settings: coordinator.dependencies.settings)
      }
  }
}

#Preview("Root") { RootView() }
#Preview("Welcome") {
  WelcomeView(coordinator: AppCoordinator(dependencies: AppDependencies.shared))
}
