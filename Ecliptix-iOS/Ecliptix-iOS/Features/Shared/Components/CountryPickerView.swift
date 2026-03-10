// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct CountryPickerView: View {

  @Environment(\.dismiss) private var dismiss
  @Binding var selectedCountry: Country
  @State private var searchText: String = ""
  var filteredCountries: [Country] {
    searchText.isEmpty
      ? Country.allCountries
      : Country.allCountries.filter {
        $0.name.localizedCaseInsensitiveContains(searchText) || $0.dialCode.contains(searchText)
      }
  }

  var body: some View {
    NavigationStack {
      List(filteredCountries) { country in
        Button(action: {
          selectedCountry = country
          dismiss()
        }) {
          HStack(spacing: 12) {
            Text(country.flag).font(.title2)
            Text(country.name).font(.geistBody).foregroundColor(.ecliptixPrimaryText)
            Spacer()
            Text(country.dialCode).font(.geistSubheadline).foregroundColor(.ecliptixSecondaryText)
            if country.code == selectedCountry.code {
              Image(systemName: "checkmark").foregroundColor(.ecliptixAccent)
            }
          }
          .accessibilityElement(children: .combine)
          .accessibilityLabel(Text("\(country.name), \(country.dialCode)"))
        }
        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
        .listRowBackground(Color.ecliptixSurface)
      }
      .searchable(text: $searchText, prompt: "Search countries")
      .navigationTitle("Select Country")
      .navigationBarTitleDisplayMode(.inline)
      .foregroundStyle(Color.ecliptixPrimaryText)
      .scrollContentBackground(.hidden)
      .background(Color.ecliptixBackground)
      .tint(.ecliptixAccent)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
            .foregroundColor(.ecliptixAccent)
        }
      }
    }
  }
}
