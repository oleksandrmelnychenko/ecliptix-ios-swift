// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension String {

  var initials: String {
    let parts = split(whereSeparator: \.isWhitespace)
    guard let first = parts.first else { return "?" }
    if parts.count == 1 {
      return String(first.prefix(2)).uppercased()
    }
    guard let last = parts.last else {
      return String(first.prefix(1)).uppercased()
    }
    return "\(first.prefix(1))\(last.prefix(1))".uppercased()
  }
}
