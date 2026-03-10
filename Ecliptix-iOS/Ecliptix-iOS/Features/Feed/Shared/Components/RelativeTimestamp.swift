// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct RelativeTimestamp: View {

  let date: Date

  private static let sameYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d"
    return f
  }()

  private static let otherYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM d, yyyy"
    return f
  }()

  var body: some View {
    Text(relativeString)
      .font(.geistFootnote)
      .foregroundStyle(Color.ecliptixSecondaryText)
  }

  private var relativeString: String {
    let now = Date()
    let interval = now.timeIntervalSince(date)

    if interval < 60 {
      return String(localized: "now")
    } else if interval < 3600 {
      let minutes = Int(interval / 60)
      return "\(minutes)m"
    } else if interval < 86400 {
      let hours = Int(interval / 3600)
      return "\(hours)h"
    } else if interval < 604800 {
      let days = Int(interval / 86400)
      return "\(days)d"
    } else {
      if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
        return Self.sameYearFormatter.string(from: date)
      } else {
        return Self.otherYearFormatter.string(from: date)
      }
    }
  }
}
