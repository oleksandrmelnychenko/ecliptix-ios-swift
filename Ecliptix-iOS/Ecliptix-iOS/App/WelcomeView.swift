// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import SwiftUI

struct WelcomeView: View {

  var coordinator: AppCoordinator
  @State private var currentSlide = 0
  @State private var glowPulse = false
  @State private var flowPhase: CGFloat = 0
  @State private var isOnline = true
  @State private var showEppInfo = false
  @State private var showLanguagePicker = false
  @State private var showLanguageSuggestion = false
  @State private var detectedLanguage: SupportedLanguage?
  @State private var selectedLanguage: SupportedLanguage = .english
  @State private var reachability = ReachabilityService()
  @State private var startupNoticeDismissTask: Task<Void, Never>?
  private var slides: [(title: String, description: String)] {
    [
      (
        l("AI Powered Safety"),
        l("Your personal AI companion monitors and protects your mental wellbeing")
      ),
      (
        l("Mental Protection"),
        l("Real-time content filtering and emotional support when you need it most")
      ),
      (
        l("Smart Communities"),
        l("Connect with friends in verified, positive spaces designed for your safety")
      ),
      (
        l("Wellness First"),
        l("Track your emotional health with insights and suggestions from our AI")
      ),
    ]
  }

  private func l(_ key: String) -> String {
    let langCode = selectedLanguage == .english ? "en" : "uk"
    guard let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
      let bundle = Bundle(path: path)
    else {
      return key
    }

    let result = bundle.localizedString(forKey: key, value: nil, table: nil)
    return result == key ? key : result
  }

  var body: some View {
    ZStack(alignment: .top) {
      EcliptixScreenBackground()
        .onTapGesture {
          if showEppInfo || showLanguagePicker {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
              showEppInfo = false
              showLanguagePicker = false
            }
          }
        }
      VStack(spacing: 0) {
        headerBar
          .padding(.horizontal, 20)
          .padding(.top, 12)
        Spacer().frame(height: 16)
        branding
        Spacer().frame(height: 20)
        auraIllustration
        Spacer().frame(height: 20)
        carouselSection
        Spacer().frame(height: 28)
        buttons
          .padding(.horizontal, 24)
        Spacer()
        footerText
        Spacer().frame(height: 16)
      }
      if showEppInfo {
        eppInfoPopup
          .padding(.top, 48)
          .padding(.leading, 20)
          .frame(maxWidth: .infinity, alignment: .leading)
          .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
          .zIndex(10)
      }
      if showLanguagePicker {
        languagePickerPopup
          .padding(.top, 48)
          .padding(.trailing, 20)
          .frame(maxWidth: .infinity, alignment: .trailing)
          .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .topTrailing)))
          .zIndex(10)
      }
      startupNoticePopup
    }
    .onAppear {
      if shouldAutoDismissStartupNotice {
        scheduleStartupNoticeDismiss()
      }
    }
    .onDisappear {
      startupNoticeDismissTask?.cancel()
    }
    .onChange(of: coordinator.startupNotice) { _, notice in
      startupNoticeDismissTask?.cancel()
      guard shouldAutoDismissStartupNotice, notice != nil else { return }
      scheduleStartupNoticeDismiss()
    }
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
          currentSlide = (currentSlide + 1) % slides.count
        }
      }
    }
    .task {
      isOnline = reachability.isConnected
      for await state in reachability.observeConnectivity() {
        switch state {
        case .connected:
          let wasOffline = !isOnline
          isOnline = true
          if wasOffline, coordinator.startupNotice?.kind == .noInternet {
            startupNoticeDismissTask?.cancel()
            withAnimation(.ecliptixSnappy) {
              coordinator.dismissStartupNotice()
            }
          }
        case .disconnected:
          isOnline = false
        default:
          break
        }
      }
    }
    .task {
      let key = "hasShownLanguageSuggestion"
      guard !UserDefaults.standard.bool(forKey: key) else { return }
      guard selectedLanguage == .english else { return }
      let result = await IpGeolocationService.shared.getIpCountry()
      if let country = result.ok() {
        let suggested = SupportedLanguage.from(countryCode: country.country)
        if let suggested, suggested != selectedLanguage {
          detectedLanguage = suggested
          try? await Task.sleep(for: .seconds(1.2))
          UserDefaults.standard.set(true, forKey: key)
          showLanguageSuggestion = true
        }
      }
    }
    .overlay(alignment: .bottom) {
      if showLanguageSuggestion, let lang = detectedLanguage {
        LanguageSuggestionSheet(
          language: lang,
          onAccept: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
              selectLanguage(lang)
              showLanguageSuggestion = false
            }
          },
          onDismiss: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
              showLanguageSuggestion = false
            }
          }
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showLanguageSuggestion)
  }

  private var headerBar: some View {
    HStack(spacing: 6) {
      eppBadge
      networkBadge
      Spacer()
      languageButton
    }
  }

  @ViewBuilder
  private var startupNoticePopup: some View {
    if let notice = coordinator.startupNotice {
      StartupConnectivityCard(
        title: startupNoticeTitle(for: notice),
        message: notice.message,
        isRetrying: coordinator.isStartupInProgress,
        onRetry: {
          Task {
            await coordinator.startup(settings: coordinator.dependencies.settings)
          }
        },
        onDismiss: {
          withAnimation(.ecliptixSnappy) {
            coordinator.dismissStartupNotice()
          }
        }
      )
      .padding(.top, 58)
      .padding(.horizontal, 20)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
      .transition(.move(edge: .top).combined(with: .opacity))
      .zIndex(6)
    }
  }

  private func startupNoticeTitle(for notice: StartupNotice) -> String {
    switch notice.kind {
    case .noInternet:
      return String(localized: "No internet connection")
    case .serverUnavailable:
      return String(localized: "Server unavailable")
    }
  }

  private var shouldAutoDismissStartupNotice: Bool {
    coordinator.startupNotice?.kind == .serverUnavailable
  }

  private func scheduleStartupNoticeDismiss() {
    startupNoticeDismissTask?.cancel()
    startupNoticeDismissTask = Task {
      try? await Task.sleep(for: .seconds(4.5))
      guard !Task.isCancelled else { return }
      await MainActor.run {
        withAnimation(.ecliptixSnappy) {
          coordinator.dismissStartupNotice()
        }
      }
    }
  }

  private var eppBadge: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showEppInfo.toggle()
        showLanguagePicker = false
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: "shield.fill")
          .font(.geist(.medium, size: 10))
        Text("EPP")
          .font(.geist(.medium, size: 11))
      }
      .foregroundColor(.ecliptixSecondaryText)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .frame(height: 28)
      .background(Color.ecliptixSurface.opacity(0.5))
      .clipShape(Capsule())
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .buttonStyle(.plain)
  }

  private var eppInfoPopup: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 8) {
        Image(systemName: "shield.fill")
          .font(.geist(.medium, size: 12))
          .foregroundColor(.ecliptixPrimaryText)
        Text(l("Ecliptix Protection Protocol"))
          .font(.geist(.medium, size: 13))
          .foregroundColor(.ecliptixPrimaryText)
      }
      VStack(alignment: .leading, spacing: 6) {
        eppFeatureRow(icon: "lock.fill", text: l("End-to-end encrypted communications"))
        eppFeatureRow(
          icon: "arrow.triangle.2.circlepath", text: l("Perfect forward secrecy for all messages"))
        eppFeatureRow(icon: "key.fill", text: l("Passwords and PIN never leave device"))
      }
    }
    .padding(12)
    .frame(width: 260, alignment: .leading)
    .background(Color.ecliptixSurfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.ecliptixStroke, lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.3), radius: 16, y: 4)
  }

  private func eppFeatureRow(icon: String, text: String) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.geist(.regular, size: 10))
        .foregroundColor(.ecliptixSecondaryText)
        .frame(width: 16)
      Text(text)
        .font(.geist(.regular, size: 12))
        .foregroundColor(.ecliptixSecondaryText)
    }
  }

  private var networkBadge: some View {
    HStack(spacing: 4) {
      Circle()
        .fill(isOnline ? Color.ecliptixOnlineIndicator : Color.ecliptixTertiaryText)
        .frame(width: 6, height: 6)
      Text(isOnline ? l("Online") : l("Offline"))
        .font(.geist(.medium, size: 11))
    }
    .foregroundColor(.ecliptixSecondaryText)
    .padding(.horizontal, 10)
    .padding(.vertical, 4)
    .frame(height: 28)
    .background(Color.ecliptixSurface.opacity(0.5))
    .clipShape(Capsule())
    .animation(.ecliptixSnappy, value: isOnline)
  }

  private var languageButton: some View {
    Button {
      withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
        showLanguagePicker.toggle()
        showEppInfo = false
      }
    } label: {
      Text(selectedLanguage.shortCode)
        .font(.geist(.medium, size: 11))
        .foregroundColor(.ecliptixSecondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(height: 28)
        .background(Color.ecliptixSecondaryButton)
        .clipShape(Capsule())
    }
    .frame(minHeight: 44)
    .contentShape(Rectangle())
    .buttonStyle(.plain)
  }

  private var languagePickerPopup: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(l("Supported languages"))
          .font(.geist(.semiBold, size: 13))
          .foregroundColor(.ecliptixPrimaryText)
        Text(l("Choose your preferred language"))
          .font(.geist(.regular, size: 11))
          .foregroundColor(.ecliptixSecondaryText)
      }
      VStack(spacing: 0) {
        ForEach(SupportedLanguage.allCases, id: \.self) { lang in
          Button {
            selectLanguage(lang)
          } label: {
            HStack(spacing: 12) {
              Text(lang.flag)
                .font(.system(size: 22))
              VStack(alignment: .leading, spacing: 1) {
                Text(lang.displayName)
                  .font(.geist(.medium, size: 13))
                  .foregroundColor(.ecliptixPrimaryText)
                Text(lang.nativeName)
                  .font(.geist(.regular, size: 11))
                  .foregroundColor(.ecliptixSecondaryText)
              }
              Spacer()
              if lang == selectedLanguage {
                Image(systemName: "checkmark")
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundColor(.ecliptixPrimaryText)
              }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
              lang == selectedLanguage
                ? Color.ecliptixSurface
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(12)
    .frame(width: 240, alignment: .leading)
    .background(Color.ecliptixSurfaceElevated)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
  }

  private func selectLanguage(_ lang: SupportedLanguage) {
    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
      selectedLanguage = lang
      showLanguagePicker = false
    }
    LocalizationService.shared.setCulture(lang.cultureCode)
  }

  private var branding: some View {
    VStack(spacing: 10) {
      Image("EcliptixLogo")
        .resizable()
        .scaledToFit()
        .frame(width: 88, height: 88)
        .accessibilityHidden(true)
      Image("EcliptixWordmark")
        .resizable()
        .scaledToFit()
        .frame(height: 26)
        .accessibilityLabel("EcliptiX")
    }
  }

  @State private var orbitRotation: Double = 0
  @State private var particlePhase: Double = 0
  private let nodeAngles: [Double] = [-90, -18, 54, 126, 198]
  private let nodeIcons: [String] = [
    "shield.fill", "bubble.left.fill", "play.fill", "heart.fill", "person.2.fill",
  ]
  private var auraIllustration: some View {
    let size: CGFloat = 260
    let r: CGFloat = 72
    let outerR: CGFloat = 110
    return ZStack {
      orbitRings(size: size, r: r, outerR: outerR)
      auraLogo
      nodeIcons(r: r)
    }
    .frame(width: size, height: size)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Ecliptix: security, messaging, media, wellness, community")
    .onAppear {
      glowPulse = true
      flowPhase = 10
      orbitRotation = 360
      withAnimation(.linear(duration: 20).repeatForever(autoreverses: false)) {
        particlePhase = 360
      }
    }
    .onDisappear {
      glowPulse = false
      flowPhase = 0
      orbitRotation = 0
      particlePhase = 0
    }
  }

  private func orbitRings(size: CGFloat, r: CGFloat, outerR: CGFloat) -> some View {
    let c: CGFloat = size / 2
    return ZStack {
      Circle()
        .stroke(Color.white.opacity(0.25), lineWidth: 1)
        .frame(width: outerR * 2, height: outerR * 2)
      Circle()
        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 6]))
        .foregroundStyle(Color.white.opacity(0.3))
        .frame(width: r * 2, height: r * 2)
        .rotationEffect(.degrees(orbitRotation))
        .animation(.linear(duration: 60).repeatForever(autoreverses: false), value: orbitRotation)
      ForEach(0..<nodeAngles.count, id: \.self) { i in
        let rad = Angle.degrees(nodeAngles[i]).radians
        Path { path in
          path.move(to: CGPoint(x: c, y: c))
          path.addLine(to: CGPoint(x: c + cos(rad) * r, y: c + sin(rad) * r))
        }
        .stroke(
          Color.white.opacity(0.18),
          style: StrokeStyle(lineWidth: 0.8, dash: [3, 4], dashPhase: flowPhase)
        )
        .frame(width: size, height: size)
      }
      .animation(.linear(duration: 2).repeatForever(autoreverses: false), value: flowPhase)
      ForEach(0..<8, id: \.self) { i in
        let a = Angle.degrees(Double(i) * 45.0 + particlePhase).radians
        Circle()
          .fill(Color.white.opacity(0.6))
          .frame(width: 4, height: 4)
          .offset(x: cos(a) * outerR, y: sin(a) * outerR)
      }
      Circle()
        .stroke(Color.white.opacity(0.25), lineWidth: 1)
        .frame(width: 56, height: 56)
        .scaleEffect(glowPulse ? 2.8 : 1.0)
        .opacity(glowPulse ? 0 : 0.6)
        .animation(
          .spring(.smooth(duration: 3.5)).repeatForever(autoreverses: false), value: glowPulse)
    }
  }

  private var auraLogo: some View {
    Image("AuraLogo")
      .resizable()
      .scaledToFit()
      .frame(width: 48, height: 48)
      .shadow(color: .white.opacity(0.2), radius: 20)
  }

  private func nodeIcons(r: CGFloat) -> some View {
    ZStack {
      iconAt("shield.fill", x: 0, y: -r)
      iconAt("bubble.left.fill", x: r * 0.95, y: r * -0.31)
      iconAt("play.fill", x: r * 0.59, y: r * 0.81)
      iconAt("heart.fill", x: r * -0.59, y: r * 0.81)
      iconAt("person.2.fill", x: r * -0.95, y: r * -0.31)
    }
  }

  @ViewBuilder
  private func iconAt(_ name: String, x: CGFloat, y: CGFloat) -> some View {
    Image(systemName: name)
      .font(.geist(.semiBold, size: 16))
      .foregroundColor(.white)
      .frame(width: 38, height: 38)
      .background(Color.white.opacity(0.1), in: Circle())
      .offset(x: x, y: y)
  }

  private var carouselSection: some View {
    VStack(spacing: 12) {
      slideContent
      slideIndicators
    }
    .contentShape(Rectangle())
    .gesture(
      DragGesture(minimumDistance: 30)
        .onEnded { value in
          if value.translation.width < -50 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
              currentSlide = (currentSlide + 1) % slides.count
            }
          } else if value.translation.width > 50 {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
              currentSlide = (currentSlide - 1 + slides.count) % slides.count
            }
          }
        }
    )
  }

  private var slideContent: some View {
    VStack(spacing: 6) {
      Text(slides[currentSlide].title)
        .font(.geist(.regular, size: 16))
        .foregroundColor(.ecliptixPrimaryText)
      Text(slides[currentSlide].description)
        .font(.geist(.regular, size: 13))
        .foregroundColor(.ecliptixTertiaryText)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .padding(.horizontal, 32)
    }
    .frame(height: 72)
    .frame(maxWidth: .infinity)
    .id(currentSlide)
    .transition(
      .asymmetric(
        insertion: .opacity.combined(with: .offset(x: 20)),
        removal: .opacity.combined(with: .offset(x: -20))
      ))
  }

  private var slideIndicators: some View {
    HStack(spacing: 4) {
      ForEach(0..<slides.count, id: \.self) { index in
        Capsule()
          .fill(index == currentSlide ? Color.white.opacity(0.9) : Color.white.opacity(0.15))
          .frame(width: index == currentSlide ? 24 : 6, height: 6)
          .animation(.ecliptixSmooth, value: currentSlide)
          .padding(19)
          .contentShape(Rectangle())
          .onTapGesture {
            withAnimation(.ecliptixSmooth) {
              currentSlide = index
            }
          }
      }
    }
  }

  private var buttons: some View {
    HStack(spacing: 12) {
      Button(action: { coordinator.navigateToSignIn() }) {
        Text(l("Sign In"))
          .font(.geist(.medium, size: 15))
          .frame(maxWidth: .infinity)
          .frame(height: 46)
          .foregroundColor(.ecliptixSecondaryButtonText)
          .background(Color.ecliptixSecondaryButton)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
          )
      }
      .buttonStyle(.plain)
      Button(action: { coordinator.navigateToRegistration() }) {
        Text(l("Sign Up"))
          .font(.geist(.medium, size: 15))
          .frame(maxWidth: .infinity)
          .frame(height: 46)
          .foregroundColor(.ecliptixPrimaryButtonText)
          .background(
            LinearGradient(
              colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
      }
      .buttonStyle(.plain)
    }
  }

  private var footerText: some View {
    Text(l("\u{00A9} 2026 Horizon Dynamics. All rights reserved."))
      .font(.geistCaption2)
      .foregroundColor(.ecliptixSecondaryText.opacity(0.5))
  }
}

enum SupportedLanguage: String, CaseIterable {
  case english
  case ukrainian
  var cultureCode: String {
    switch self {
    case .english: "en-US"
    case .ukrainian: "uk-UA"
    }
  }

  var flag: String {
    switch self {
    case .english: "\u{1F1FA}\u{1F1F8}"
    case .ukrainian: "\u{1F1FA}\u{1F1E6}"
    }
  }

  var shortCode: String {
    switch self {
    case .english: "EN"
    case .ukrainian: "UA"
    }
  }

  var displayName: String {
    switch self {
    case .english: "English"
    case .ukrainian: "Ukrainian"
    }
  }

  var nativeName: String {
    switch self {
    case .english: "English"
    case .ukrainian:
      "\u{0423}\u{043A}\u{0440}\u{0430}\u{0457}\u{043D}\u{0441}\u{044C}\u{043A}\u{0430}"
    }
  }

  static func from(cultureCode: String) -> SupportedLanguage {
    allCases.first { $0.cultureCode == cultureCode } ?? .english
  }

  static func from(countryCode: String) -> SupportedLanguage? {
    switch countryCode.uppercased() {
    case "UA": return .ukrainian
    default: return nil
    }
  }
}

struct LanguageSuggestionSheet: View {

  let language: SupportedLanguage
  let onAccept: () -> Void
  let onDismiss: () -> Void
  @State private var rotationY: Double = 0
  @State private var floatOffset: CGFloat = 0
  @State private var shimmer: Double = 0
  var body: some View {
    VStack(spacing: 12) {
      Capsule()
        .fill(Color.ecliptixSecondaryText.opacity(0.3))
        .frame(width: 36, height: 5)
        .padding(.top, 8)
      HStack(spacing: 14) {
        ZStack {
          Circle()
            .fill(
              RadialGradient(
                colors: flagGlowColors,
                center: .center,
                startRadius: 4,
                endRadius: 28
              )
            )
            .frame(width: 56, height: 56)
            .opacity(0.35)
            .blur(radius: 10)
          Text(language.flag)
            .font(.system(size: 38))
            .rotation3DEffect(.degrees(rotationY), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .offset(y: floatOffset)
        }
        .frame(width: 56, height: 56)
        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Switch to \(language.nativeName)?"))
            .font(.geist(.semiBold, size: 15))
            .foregroundColor(.ecliptixPrimaryText)
          Text(String(localized: "It looks like you're in \(regionName)"))
            .font(.geist(.regular, size: 12))
            .foregroundColor(.ecliptixSecondaryText)
        }
      }
      .padding(.horizontal, 16)
      HStack(spacing: 8) {
        Button(action: onDismiss) {
          Text("English")
            .font(.geist(.medium, size: 14))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundColor(.ecliptixSecondaryButtonText)
            .background(Color.ecliptixSecondaryButton)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
              RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        Button(action: onAccept) {
          Text(language.nativeName)
            .font(.geist(.medium, size: 14))
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .foregroundColor(.ecliptixPrimaryButtonText)
            .background(
              LinearGradient(
                colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
                startPoint: .leading,
                endPoint: .trailing
              )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 14)
    }
    .background(
      Color.ecliptixSurfaceElevated
        .shadow(.drop(color: .black.opacity(0.25), radius: 20, y: -4))
    )
    .clipShape(RoundedRectangle(cornerRadius: 20))
    .overlay(
      RoundedRectangle(cornerRadius: 20)
        .stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
    )
    .padding(.horizontal, 12)
    .background(Color.ecliptixSurfaceElevated.ignoresSafeArea(edges: .bottom))
    .onAppear {
      withAnimation(.spring(.smooth(duration: 4)).repeatForever(autoreverses: true)) {
        rotationY = 25
      }
      withAnimation(.spring(.smooth(duration: 2.5)).repeatForever(autoreverses: true)) {
        floatOffset = -6
      }
    }
  }

  private var flagGlowColors: [Color] {
    switch language {
    case .ukrainian: [Color(hex: 0x005BBB), Color(hex: 0xFFD500), .clear]
    case .english: [Color(hex: 0x3C3B6E), Color(hex: 0xB22234), .clear]
    }
  }

  private var regionName: String {
    switch language {
    case .ukrainian: "Ukraine"
    case .english: "the United States"
    }
  }
}

struct StartupConnectivityCard: View {

  let title: String
  let message: String
  let isRetrying: Bool
  let onRetry: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "wifi.exclamationmark")
          .font(.geist(.semiBold, size: 16))
          .foregroundColor(.ecliptixWarning)
          .frame(width: 28, height: 28)
          .background(Color.ecliptixWarning.opacity(0.12), in: Circle())
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(title)
            .font(.geist(.semiBold, size: 14))
            .foregroundColor(.ecliptixPrimaryText)
          Text(message)
            .font(.geist(.regular, size: 12))
            .foregroundColor(.ecliptixSecondaryText)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
        Button(action: onDismiss) {
          Image(systemName: "xmark")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.ecliptixSecondaryText)
            .frame(width: 28, height: 28)
            .background(Color.ecliptixSecondaryButton, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Dismiss"))
      }

      Button(action: onRetry) {
        HStack(spacing: 8) {
          if isRetrying {
            ProgressView()
              .progressViewStyle(CircularProgressViewStyle(tint: .ecliptixPrimaryButtonText))
              .scaleEffect(0.8)
          }
          Text(isRetrying ? String(localized: "Retrying...") : String(localized: "Retry"))
            .font(.geist(.medium, size: 14))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 42)
        .foregroundColor(.ecliptixPrimaryButtonText)
        .background(
          LinearGradient(
            colors: [.ecliptixPrimaryButtonGradientStart, .ecliptixPrimaryButtonGradientEnd],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
      }
      .buttonStyle(.plain)
      .disabled(isRetrying)
      .opacity(isRetrying ? 0.7 : 1)
    }
    .padding(14)
    .background(Color.ecliptixSurfaceElevated.opacity(0.92))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.ecliptixMutedStroke, lineWidth: 0.5)
    )
    .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
  }
}
