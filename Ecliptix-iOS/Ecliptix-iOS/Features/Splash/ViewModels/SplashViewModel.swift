// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

@Observable @MainActor
final class SplashViewModel {

  var opacity: Double = 0.0
  var scale: Double = 0.9

  func resetAnimationState() {
    opacity = 0.0
    scale = 0.9
  }

  func onAppear() {
    opacity = 1.0
    scale = 1.0
  }
}
