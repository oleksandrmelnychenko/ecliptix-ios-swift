// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct StreamReconnectPolicy: Sendable {

  let maxRetryCount: Int
  let initialDelay: TimeInterval
  let maxDelay: TimeInterval
  let jitterRange: ClosedRange<Double>

  static let `default` = StreamReconnectPolicy(
    maxRetryCount: 10,
    initialDelay: 1.0,
    maxDelay: 60.0,
    jitterRange: 0...0.5
  )

  func delay(forAttempt attempt: Int) -> TimeInterval {
    let boundedAttempt = max(1, attempt)
    let exponentialDelay = initialDelay * pow(2.0, Double(boundedAttempt - 1))
    let cappedDelay = min(exponentialDelay, maxDelay)
    let jitter = Double.random(in: jitterRange)
    return cappedDelay + jitter
  }
}
