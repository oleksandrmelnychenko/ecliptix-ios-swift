// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct SplashView: View {

  @State private var viewModel: SplashViewModel
  init(viewModel: SplashViewModel) {
    _viewModel = State(wrappedValue: viewModel)
  }

  var body: some View {
    ZStack {
      StartupBranding.splashBackgroundColor
        .ignoresSafeArea()
      Image(StartupAssetName.splashLogo.rawValue)
        .resizable()
        .scaledToFit()
        .frame(width: 180, height: 180)
        .scaleEffect(viewModel.scale)
        .opacity(viewModel.opacity)
        .accessibilityLabel(Text("Ecliptix logo"))
    }
    .onAppear {
      viewModel.resetAnimationState()
      withAnimation(.spring(.smooth(duration: 0.5))) {
        viewModel.onAppear()
      }
    }
  }
}

#Preview {
  SplashView(viewModel: SplashViewModel())
}
