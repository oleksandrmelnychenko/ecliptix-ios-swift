// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

@Observable @MainActor
final class PinSetupViewModel: Resettable {

  var pin: String = "" {
    didSet {
      let sanitized = String(pin.prefix(pinLength).filter(\.isNumber))
      if pin != sanitized { pin = sanitized }
    }
  }

  var confirmPin: String = "" {
    didSet {
      let sanitized = String(confirmPin.prefix(pinLength).filter(\.isNumber))
      if confirmPin != sanitized { confirmPin = sanitized }
    }
  }

  var isConfirmStep: Bool = false
  var pinError: String = ""
  var isBusy: Bool = false
  var hasPinError: Bool { !pinError.isEmpty }
  var stepBadgeText: String { String(localized: "Step 4 of 6") }
  var title: String {
    isConfirmStep ? String(localized: "Confirm PIN") : String(localized: "Create PIN")
  }

  var subtitle: String {
    isConfirmStep
      ? String(localized: "Re-enter your 4-digit PIN to confirm")
      : String(localized: "Create a 4-digit PIN for quick access to your account")
  }

  var buttonText: String {
    isConfirmStep ? String(localized: "Confirm") : String(localized: "Continue")
  }

  var canProceed: Bool {
    let currentPin = isConfirmStep ? confirmPin : pin
    return currentPin.count == pinLength && currentPin.allSatisfy(\.isNumber) && !isBusy
  }

  private let pinLength: Int = 4
  private let pinOpaqueService: PinOpaqueService
  private let secureStorageService: SecureStorageService
  private let connectIdProvider: (PubKeyExchangeType) -> ConnectId
  private let onPinSetupCompleted: () -> Void

  init(
    pinOpaqueService: PinOpaqueService,
    secureStorageService: SecureStorageService,
    connectIdProvider: @escaping (PubKeyExchangeType) -> ConnectId,
    onPinSetupCompleted: @escaping () -> Void = {}
  ) {
    self.pinOpaqueService = pinOpaqueService
    self.secureStorageService = secureStorageService
    self.connectIdProvider = connectIdProvider
    self.onPinSetupCompleted = onPinSetupCompleted
  }

  func proceed() async {
    guard canProceed else { return }
    if isConfirmStep {
      await confirmAndSet()
    } else {
      pinError = ""
      isConfirmStep = true
    }
  }

  func goBack() {
    guard isConfirmStep, !isBusy else { return }
    confirmPin = ""
    isConfirmStep = false
    pinError = ""
  }

  func resetState() {
    pin = ""
    confirmPin = ""
    isConfirmStep = false
    pinError = ""
    isBusy = false
  }

  private func confirmAndSet() async {
    guard pin == confirmPin else {
      pinError = String(localized: "PINs don't match. Please try again.")
      confirmPin = ""
      isConfirmStep = false
      pin = ""
      return
    }
    isBusy = true
    defer { isBusy = false }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    var pinBytes = Data(pin.utf8)
    pin = ""
    confirmPin = ""
    let securePin = SecureTextBuffer(consuming: &pinBytes)
    OpaqueNative.secureZeroData(&pinBytes)
    defer { securePin.dispose() }

    let result = await pinOpaqueService.registerPin(
      pinCode: securePin,
      pinLength: Int32(pinLength),
      connectId: connectId
    )
    guard result.isOk else {
      guard let failure = result.err() else { return }
      AppLogger.auth.error(
        "PinSetup: PIN OPAQUE register failed, error=\(failure.message, privacy: .public)")
      pinError = mapPinFailureToUserMessage(failure)
      isConfirmStep = false
      return
    }
    _ = await secureStorageService.setRegistrationCheckpoint(.pinCredentialSet)
    AppLogger.auth.info("PinSetup: PIN set successfully")
    onPinSetupCompleted()
  }

  private func mapPinFailureToUserMessage(_ failure: PinOpaqueFailure) -> String {
    switch failure {
    case .invalidPinLength:
      return String(localized: "Invalid PIN length.")
    case .accountNotFound:
      return String(localized: "Account not found.")
    case .networkFailed(let rpcError):
      return rpcError.userFacingMessage
    default:
      return ServerErrorMapper.userFacingMessage(failure.message)
    }
  }
}
