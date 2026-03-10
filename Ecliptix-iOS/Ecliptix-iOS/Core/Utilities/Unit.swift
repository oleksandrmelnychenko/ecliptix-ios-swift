// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

struct Unit: Equatable, Hashable {

  static let value = Unit()

  private init() {}

  static func == (lhs: Unit, rhs: Unit) -> Bool {
    true
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(0)
  }
}

extension Unit: CustomStringConvertible {

  var description: String {
    "()"
  }
}
