// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct CheckboxToggleStyle: ToggleStyle {

  func makeBody(configuration: Configuration) -> some View {
    Button(action: {
      configuration.isOn.toggle()
    }) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
          .font(.title3)
          .foregroundColor(configuration.isOn ? .ecliptixAccent : .ecliptixSecondaryText)
          .accessibilityHidden(true)
        configuration.label
      }
    }
    .buttonStyle(PlainButtonStyle())
    .accessibilityAddTraits(.isToggle)
    .accessibilityValue(configuration.isOn ? Text("Checked") : Text("Unchecked"))
  }
}
