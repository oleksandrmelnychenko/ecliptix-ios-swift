// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum IdentifierValidation {

  static let maxAllowedZeroBytes = 12

  static func isValidGuidIdentifier(_ data: Data) -> Bool {
    guard data.count == AppConstants.Crypto.guidBytesCount else { return false }
    var zeroCount = 0
    for byte in data where byte == 0 {
      zeroCount += 1
    }
    return zeroCount <= maxAllowedZeroBytes
  }
}
