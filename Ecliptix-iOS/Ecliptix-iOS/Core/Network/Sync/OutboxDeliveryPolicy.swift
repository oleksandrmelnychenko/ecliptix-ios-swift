// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct OutboxDeliveryPolicy: Sendable {

  let maxBatchSize: Int
  let maxRetryCount: Int
  let initialBackoffDelay: TimeInterval
  let maxBackoffDelay: TimeInterval
  let diagnosticsPageSize: Int

  static let `default` = OutboxDeliveryPolicy(
    maxBatchSize: 20,
    maxRetryCount: 5,
    initialBackoffDelay: 2.0,
    maxBackoffDelay: 60.0,
    diagnosticsPageSize: 50
  )

  func backoffDelay(forRetryCount retryCount: Int) -> TimeInterval {
    let boundedRetryCount = max(1, retryCount)
    let exponentialDelay = initialBackoffDelay * pow(2.0, Double(boundedRetryCount - 1))
    return min(maxBackoffDelay, exponentialDelay)
  }
}
