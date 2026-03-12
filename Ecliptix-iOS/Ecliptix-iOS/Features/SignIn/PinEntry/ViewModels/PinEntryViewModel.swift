// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation
import os.log

@Observable @MainActor
final class PinEntryViewModel: Resettable {

  var pin: String = "" {
    didSet {
      let sanitized = String(pin.prefix(pinLength).filter(\.isNumber))
      if pin != sanitized { pin = sanitized }
    }
  }

  var pinError: String = ""
  var isBusy: Bool = false
  var remainingAttempts: Int = -1
  var isLocked: Bool = false
  var hasPinError: Bool { !pinError.isEmpty }
  var canVerify: Bool {
    pin.count == pinLength && pin.allSatisfy(\.isNumber) && !isBusy && !isLocked
  }

  private let pinLength: Int = 4
  private let pinOpaqueService: PinOpaqueService
  private let secureStorageService: SecureStorageService
  private let settingsProvider: () -> ApplicationInstanceSettings?
  private let connectIdProvider: (PubKeyExchangeType) -> ConnectId
  private let onPinVerified: () -> Void
  private let onPinSetupRequired: () -> Void

  init(
    pinOpaqueService: PinOpaqueService,
    secureStorageService: SecureStorageService,
    settingsProvider: @escaping () -> ApplicationInstanceSettings?,
    connectIdProvider: @escaping (PubKeyExchangeType) -> ConnectId,
    onPinVerified: @escaping () -> Void = {},
    onPinSetupRequired: @escaping () -> Void = {}
  ) {
    self.pinOpaqueService = pinOpaqueService
    self.secureStorageService = secureStorageService
    self.settingsProvider = settingsProvider
    self.connectIdProvider = connectIdProvider
    self.onPinVerified = onPinVerified
    self.onPinSetupRequired = onPinSetupRequired
  }

  func verifyPin() async {
    guard canVerify else { return }
    pinError = ""
    isBusy = true
    defer { isBusy = false }

    let settings = settingsProvider()
    guard let accountId = settings?.currentAccountId else {
      AppLogger.auth.error("PinEntry: missing accountId in stored settings")
      pinError = String(localized: "Missing account information")
      return
    }

    let connectId = connectIdProvider(.dataCenterEphemeralConnect)
    var pinBytes = Data(pin.utf8)
    pin = ""
    let securePin = SecureTextBuffer(consuming: &pinBytes)
    OpaqueNative.secureZeroData(&pinBytes)
    defer { securePin.dispose() }

    let result = await pinOpaqueService.verifyPin(
      accountId: accountId,
      pinCode: securePin,
      connectId: connectId
    )
    guard result.isOk else {
      guard let failure = result.err() else { return }
      AppLogger.auth.error(
        "PinEntry: PIN OPAQUE verify failed, error=\(failure.message, privacy: .public)")
      switch failure {
      case .locked(let remaining, _):
        isLocked = true
        AppLogger.auth.warning(
          "PinEntry: account locked for accountId=\(accountId.uuidString, privacy: .public), lockoutSeconds=\(remaining, privacy: .public)"
        )
        pinError = String(localized: "Account locked. Too many failed attempts.")
      case .attemptsExceeded(let remaining, _):
        isLocked = true
        remainingAttempts = Int(remaining)
        AppLogger.auth.warning(
          "PinEntry: attempts exceeded for accountId=\(accountId.uuidString, privacy: .public)")
        pinError = String(localized: "Account locked. Too many failed attempts.")
      case .invalidPin(let remaining, _):
        if remaining > 0 {
          remainingAttempts = Int(remaining)
          AppLogger.auth.warning(
            "PinEntry: incorrect PIN for accountId=\(accountId.uuidString, privacy: .public), remaining=\(remaining, privacy: .public)"
          )
          pinError = String(
            format: String(localized: "Incorrect PIN. %d attempts remaining."),
            remainingAttempts
          )
        } else {
          AppLogger.auth.warning(
            "PinEntry: incorrect PIN for accountId=\(accountId.uuidString, privacy: .public)")
          pinError = String(localized: "Incorrect PIN. Please try again.")
        }
      case .notRegistered:
        AppLogger.auth.warning(
          "PinEntry: PIN not registered for accountId=\(accountId.uuidString, privacy: .public)")
        let checkpointResult = await secureStorageService.setRegistrationCheckpoint(
          .primaryCredentialSet)
        if let checkpointError = checkpointResult.err() {
          AppLogger.auth.warning(
            "PinEntry: failed to downgrade stale checkpoint for accountId=\(accountId.uuidString, privacy: .public), error=\(checkpointError, privacy: .public)"
          )
        }
        onPinSetupRequired()
      case .accountNotFound:
        pinError = String(localized: "Account not found.")
      case .networkFailed(let rpcError):
        pinError = rpcError.userFacingMessage
      default:
        pinError = ServerErrorMapper.userFacingMessage(failure.message)
      }
      return
    }
    AppLogger.auth.info(
      "PinEntry: PIN verified successfully for accountId=\(accountId.uuidString, privacy: .public)")
    onPinVerified()
  }

  func resetState() {
    pin = ""
    pinError = ""
    isBusy = false
    remainingAttempts = -1
    isLocked = false
  }
}
