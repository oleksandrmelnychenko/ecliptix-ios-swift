// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension SecureKeyConfirmationViewModel {

  func submit() async {
    guard canSubmit else { return }
    serverError = ""
    isBusy = true
    var secureKeyBytes = Data(secureKey.utf8)
    let secureKeyBuffer = SecureTextBuffer(consuming: &secureKeyBytes)
    OpaqueNative.secureZeroData(&secureKeyBytes)
    secureKey = ""
    verifySecureKey = ""
    defer {
      secureKeyBuffer.dispose()
      isBusy = false
    }
    if flowContext == .registration {
      guard let resolvedMembershipIdBytes = resolveMembershipIdBytes() else {
        serverError = String(localized: "Missing membership ID for registration")
        return
      }
      guard let opaqueRegistrationService else {
        serverError = String(localized: "Registration service is not configured")
        return
      }

      let result = await opaqueRegistrationService.completeRegistration(
        membershipIdBytes: resolvedMembershipIdBytes,
        secureKey: secureKeyBuffer
      )
      guard result.isOk else {
        serverError = result.err() ?? String(localized: "Unknown error")
        return
      }
      guard let opaqueAuthService else {
        serverError = String(localized: "Authentication service is not configured")
        return
      }
      guard let mobileNumber, !mobileNumber.isEmpty else {
        serverError = String(localized: "Missing mobile number for registration completion")
        return
      }

      let connectId = connectIdProvider(.dataCenterEphemeralConnect)
      let signInResult = await opaqueAuthService.signIn(
        mobileNumber: mobileNumber,
        secureKey: secureKeyBuffer,
        connectId: connectId
      )
      guard signInResult.isOk else {
        serverError =
          signInResult.err()?.message
          ?? String(localized: "OPAQUE sign-in failed after registration")
        return
      }
      onSecureKeyConfirmed()
      return
    }
    if flowContext == .secureKeyRecovery {
      guard let resolvedMembershipIdBytes = resolveMembershipIdBytes() else {
        serverError = String(localized: "Missing membership ID for recovery")
        return
      }
      guard let secureKeyRecoveryService else {
        serverError = String(localized: "Recovery service is not configured")
        return
      }

      let result = await secureKeyRecoveryService.completeSecureKeyRecovery(
        membershipIdBytes: resolvedMembershipIdBytes,
        secureKey: secureKeyBuffer
      )
      guard result.isOk else {
        serverError = result.err() ?? String(localized: "Unknown error")
        return
      }
      onSecureKeyConfirmed()
      return
    }
    onSecureKeyConfirmed()
  }

  func resolveMembershipIdBytes() -> Data? {
    if let membershipIdBytes, !membershipIdBytes.isEmpty {
      return membershipIdBytes
    }
    guard let membershipId else {
      return nil
    }
    return membershipId.protobufBytes
  }
}
