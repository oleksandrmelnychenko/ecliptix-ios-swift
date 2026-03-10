// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

final class RegistrationStateManager {

  private let lock = NSLock()
  private var inFlightOperations: [Data: (date: Date, generation: UInt64)] = [:]
  private var generationCounter: UInt64 = 0
  private let lockTimeout: TimeInterval = 120

  func tryAcquire(_ membershipIdBytes: Data) -> UInt64? {
    lock.lock()
    defer { lock.unlock() }

    if let entry = inFlightOperations[membershipIdBytes] {
      if Date().timeIntervalSince(entry.date) < lockTimeout {
        return nil
      }
      inFlightOperations.removeValue(forKey: membershipIdBytes)
    }
    generationCounter += 1
    let gen = generationCounter
    inFlightOperations[membershipIdBytes] = (date: Date(), generation: gen)
    return gen
  }

  func release(_ membershipIdBytes: Data, generation: UInt64) {
    lock.lock()
    defer { lock.unlock() }

    if let entry = inFlightOperations[membershipIdBytes], entry.generation == generation {
      inFlightOperations.removeValue(forKey: membershipIdBytes)
    }
  }
}
