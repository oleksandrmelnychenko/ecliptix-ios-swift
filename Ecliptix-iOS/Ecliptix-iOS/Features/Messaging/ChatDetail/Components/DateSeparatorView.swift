// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct DateSeparatorView: View {

  let date: Date

  var body: some View {
    HStack {
      Spacer()

      Text(formattedDate)
        .font(.geistCaption)
        .foregroundColor(.ecliptixTertiaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(Color.ecliptixSurface.opacity(0.85))
        .clipShape(Capsule())

      Spacer()
    }
  }

  private static let currentYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM d"
    return f
  }()

  private static let otherYearFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMMM d, yyyy"
    return f
  }()

  private var formattedDate: String {
    let calendar = Calendar.current

    if calendar.isDateInToday(date) {
      return String(localized: "Today")
    }

    if calendar.isDateInYesterday(date) {
      return String(localized: "Yesterday")
    }

    let currentYear = calendar.component(.year, from: Date())
    let dateYear = calendar.component(.year, from: date)

    if dateYear == currentYear {
      return Self.currentYearFormatter.string(from: date)
    } else {
      return Self.otherYearFormatter.string(from: date)
    }
  }
}
