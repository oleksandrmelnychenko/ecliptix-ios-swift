// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os

extension OtpVerificationViewModel {

  func startAutoRedirect(seconds: Int, title: String, subtitle: String, message: String? = nil) {
    isAutoRedirecting = true
    autoRedirectTitle = title
    autoRedirectSubtitle = subtitle
    autoRedirectCountdown = max(seconds, 0)
    AppLogger.auth.warning(
      "OTP VM: auto-redirect scheduled status=\(self.currentStatus.rawValue, privacy: .public), seconds=\(seconds, privacy: .public), context=\(String(describing: self.flowContext), privacy: .public)"
    )
    if let message, !message.isEmpty { publishError(message) }
    autoRedirectTimer.start(
      seconds: seconds,
      onTick: { [weak self] remaining in
        self?.autoRedirectCountdown = remaining
      },
      onFinish: { [weak self] in
        guard let self else { return }
        self.isAutoRedirecting = false
        AppLogger.auth.info(
          "OTP VM: auto-redirect fired status=\(self.currentStatus.rawValue, privacy: .public), context=\(String(describing: self.flowContext), privacy: .public)"
        )
        self.onAutoRedirect(self.currentStatus)
      }
    )
  }
}
