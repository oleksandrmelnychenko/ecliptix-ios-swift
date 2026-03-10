// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class ExponentialBackoffStrategy: RpcRetryStrategy {

  private let retryPolicyProvider: RetryPolicyProvider

  init(retryPolicyProvider: RetryPolicyProvider) {
    self.retryPolicyProvider = retryPolicyProvider
  }

  func executeRpcOperation<T>(
    _ operation: @escaping (Int, CancellationToken) async throws -> Result<T, NetworkFailure>,
    operationName: String,
    connectId: UInt32,
    serviceType: RpcServiceType,
    maxRetries: Int? = nil,
    cancellationToken: CancellationToken
  ) async -> Result<T, NetworkFailure> {
    let policy = retryPolicyProvider.getPolicyForOperation(serviceType)
    let effectiveMaxRetries = maxRetries ?? policy.maxRetries
    var lastFailure: NetworkFailure?
    var attempt = 0
    while attempt < effectiveMaxRetries {
      if cancellationToken.cancelled {
        return .err(.operationCancelled("Operation was cancelled"))
      }
      do {
        let result = try await operation(attempt, cancellationToken)
        switch result {
        case .ok(let value):
          return .ok(value)
        case .err(let failure):
          lastFailure = failure
          if !shouldRetry(
            failure: failure, attempt: attempt, maxRetries: effectiveMaxRetries)
          {
            return .err(failure)
          }
          if attempt < effectiveMaxRetries {
            let delay = policy.calculateDelay(attempt: attempt)
            do {
              try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            } catch {
              return .err(.operationCancelled("Operation was cancelled"))
            }
          }
        }
      } catch {
        return .err(
          .connectionFailed(
            "Operation failed with exception",
            innerError: error
          ))
      }
      attempt += 1
    }
    return .err(lastFailure ?? .operationCancelled("Max retries exceeded"))
  }

  private func shouldRetry(failure: NetworkFailure, attempt: Int, maxRetries: Int) -> Bool {
    guard attempt < maxRetries else {
      return false
    }
    switch failure.failureType {
    case .dataCenterNotResponding,
      .dataCenterShutdown,
      .connectionFailed:
      return true
    case .sessionExpired,
      .operationCancelled,
      .criticalAuthenticationFailure:
      return false
    default:
      return false
    }
  }
}

final class DefaultRetryPolicyProvider: RetryPolicyProvider {

  func getPolicyForOperation(_ operationType: RpcServiceType) -> RetryPolicy {
    switch operationType {
    case .establishSecrecyChannel:
      return .aggressive
    default:
      return .default
    }
  }
}
