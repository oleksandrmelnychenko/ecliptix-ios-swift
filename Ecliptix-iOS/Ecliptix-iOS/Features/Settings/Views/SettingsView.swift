// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

enum SettingsDestination: Hashable {
  case profile
  case security
  case privacy
  #if DEBUG
    case outboxDiagnostics
  #endif
}

struct SettingsView: View {

  var coordinator: AppCoordinator
  var accountViewModel: AccountSettingsViewModel
  @AppStorage("app_theme") private var appThemeRawValue: String = AppTheme.light.rawValue
  @AppStorage("accent_color") private var accentColorRawValue: String = AccentColor.green.rawValue

  private var selectedTheme: AppTheme {
    get { AppTheme(rawValue: appThemeRawValue) ?? .light }
    nonmutating set { appThemeRawValue = newValue.rawValue }
  }

  private var selectedAccent: AccentColor {
    get { AccentColor(rawValue: accentColorRawValue) ?? .green }
    nonmutating set { accentColorRawValue = newValue.rawValue }
  }

  var body: some View {
    List {
      profileSection
      accountSection
      appearanceSection
      #if DEBUG
        diagnosticsSection
      #endif
      logoutSection
    }
    .navigationTitle(String(localized: "Settings"))
    .navigationDestination(for: SettingsDestination.self) { destination in
      switch destination {
      case .profile:
        AccountSettingsView(viewModel: accountViewModel)
      case .security:
        Text(String(localized: "Security"))
      case .privacy:
        Text(String(localized: "Privacy"))
      #if DEBUG
      case .outboxDiagnostics:
        OutboxDiagnosticsView(
          viewModel: coordinator.cachedViewModel(key: "settings.outboxDiagnostics") {
            coordinator.dependencies.makeOutboxDiagnosticsViewModel()
          }
        )
      #endif
      }
    }
    .task { await accountViewModel.loadProfile() }
  }

  private var profileSection: some View {
    Section {
      NavigationLink(value: SettingsDestination.profile) {
        HStack {
          ZStack {
            Circle()
              .fill(Color.ecliptixAccent.gradient)
              .frame(width: 44, height: 44)
            Text(accountViewModel.profileInitials)
              .font(.geist(.semiBold, size: 16))
              .foregroundStyle(.white)
          }
          .accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 4) {
            Text(
              accountViewModel.displayName.isEmpty
                ? String(localized: "User Name")
                : accountViewModel.displayName
            )
            .font(.geist(.semiBold, size: 17))
            Text(
              accountViewModel.profileName.isEmpty
                ? "@username"
                : "@\(accountViewModel.profileName)"
            )
            .font(.geistFootnote)
            .foregroundColor(.secondary)
          }
          .padding(.leading, 8)
        }
        .padding(.vertical, 8)
      }
    }
  }

  private var accountSection: some View {
    Section(String(localized: "Account")) {
      NavigationLink(value: SettingsDestination.profile) {
        Label(String(localized: "Profile"), systemImage: "person")
      }
      NavigationLink(value: SettingsDestination.security) {
        Label(String(localized: "Security"), systemImage: "lock")
      }
      NavigationLink(value: SettingsDestination.privacy) {
        Label(String(localized: "Privacy"), systemImage: "hand.raised")
      }
    }
  }

  private var appearanceSection: some View {
    Section(String(localized: "Appearance")) {
      themeRow
      accentColorRow
    }
  }

  private var themeRow: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Theme"))
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)

      HStack(spacing: 12) {
        ForEach(AppTheme.allCases) { theme in
          ThemeSwatchView(
            theme: theme,
            isSelected: selectedTheme == theme
          ) {
            withAnimation(.ecliptixSnappy) {
              selectedTheme = theme
            }
          }
        }
      }
    }
    .padding(.vertical, 8)
    .listRowBackground(Color.clear)
  }

  private var accentColorRow: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Accent Color"))
        .font(.geistSubheadline)
        .foregroundColor(.ecliptixSecondaryText)

      LazyVGrid(
        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 7),
        spacing: 12
      ) {
        ForEach(AccentColor.allCases) { accent in
          Circle()
            .fill(accent.color)
            .frame(width: 32, height: 32)
            .overlay(
              Circle()
                .stroke(Color.ecliptixPrimaryText, lineWidth: selectedAccent == accent ? 2 : 0)
                .padding(2)
            )
            .scaleEffect(selectedAccent == accent ? 1.1 : 1.0)
            .animation(.ecliptixBouncy, value: selectedAccent)
            .onTapGesture {
              withAnimation(.ecliptixSnappy) {
                selectedAccent = accent
              }
            }
            .accessibilityLabel(Text(accent.title))
            .accessibilityAddTraits(selectedAccent == accent ? .isSelected : [])
        }
      }
    }
    .padding(.vertical, 8)
    .listRowBackground(Color.clear)
  }

  private var logoutSection: some View {
    Section {
      LogoutButton(
        logoutService: coordinator.dependencies.logoutService,
        onLogoutComplete: { coordinator.handleLogout() }
      )
    }
  }

  #if DEBUG
    private var diagnosticsSection: some View {
      Section("Diagnostics") {
        NavigationLink(value: SettingsDestination.outboxDiagnostics) {
          Label("Outbox Diagnostics", systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
        }
      }
    }
  #endif
}

private struct ThemeSwatchView: View {

  let theme: AppTheme
  let isSelected: Bool
  let onSelect: () -> Void

  var body: some View {
    VStack(spacing: 6) {
      RoundedRectangle(cornerRadius: 8)
        .fill(theme.previewColor)
        .frame(width: 52, height: 36)
        .overlay(
          RoundedRectangle(cornerRadius: 8)
            .stroke(
              isSelected ? Color.ecliptixAccent : Color.ecliptixMutedStroke,
              lineWidth: isSelected ? 2 : 0.5
            )
        )
        .shadow(color: .black.opacity(0.06), radius: 2, y: 1)

      Text(theme.title)
        .font(.geistCaption2)
        .foregroundColor(isSelected ? .ecliptixPrimaryText : .ecliptixSecondaryText)
        .lineLimit(1)
    }
    .onTapGesture(perform: onSelect)
    .accessibilityLabel(Text(theme.title))
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
