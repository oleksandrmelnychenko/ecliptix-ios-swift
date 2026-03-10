// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

extension Result where E == ProtocolFailure {

  func toNetworkFailure() -> Result<T, NetworkFailure> {
    switch self {
    case .ok(let value):
      return .ok(value)
    case .err(let protocolFailure):
      return .err(protocolFailure.toNetworkFailure())
    }
  }
}

extension Result where E == AuthenticationFailure {

  func toNetworkFailure() -> Result<T, NetworkFailure> {
    mapError { authFailure in
      NetworkFailure(
        failureType: .criticalAuthenticationFailure,
        message: authFailure.message,
        innerError: authFailure.innerError
      )
    }
  }
}

extension Result where E == CryptographyFailure {

  func toProtocolFailure() -> Result<T, ProtocolFailure> {
    mapError { cryptoFailure in
      let failureType: ProtocolFailureType
      switch cryptoFailure.failureType {
      case .allocationFailed:
        failureType = .allocationFailed
      case .memoryPinningFailed:
        failureType = .pinningFailure
      case .bufferTooSmall:
        failureType = .bufferTooSmall
      case .bufferTooLarge:
        failureType = .dataTooLarge
      default:
        failureType = .generic
      }
      return ProtocolFailure(
        failureType: failureType,
        message: cryptoFailure.message,
        innerError: cryptoFailure.innerError
      )
    }
  }
}

extension Result where E == ValidationFailure {

  func toAuthenticationFailure() -> Result<T, AuthenticationFailure> {
    mapError { validationFailure in
      let failureType: AuthenticationFailureType
      switch validationFailure.failureType {
      case .loginAttemptExceeded:
        failureType = .loginAttemptExceeded
      case .signInFailed:
        failureType = .invalidCredentials
      }
      return AuthenticationFailure(
        failureType: failureType,
        message: validationFailure.message,
        innerError: validationFailure.innerError
      )
    }
  }
}

extension Result where E == LogoutFailure {

  func toNetworkFailure() -> Result<T, NetworkFailure> {
    mapError { logoutFailure in
      let failureType: NetworkFailureType
      switch logoutFailure.failureType {
      case .networkRequestFailed:
        failureType = .connectionFailed
      case .sessionNotFound:
        failureType = .sessionExpired
      case .alreadyLoggedOut:
        failureType = .sessionExpired
      case .cryptographicOperationFailed:
        failureType = .ecliptixProtocolFailure
      case .invalidRevocationProof:
        failureType = .ecliptixProtocolFailure
      case .invalidMembershipIdentifier:
        failureType = .criticalAuthenticationFailure
      case .unexpectedError:
        failureType = .connectionFailed
      }
      return NetworkFailure(
        failureType: failureType,
        message: logoutFailure.message,
        innerError: logoutFailure.innerError
      )
    }
  }
}

extension Error {

  func toNetworkFailure() -> NetworkFailure {
    if let urlError = self as? URLError {
      switch urlError.code {
      case .notConnectedToInternet, .networkConnectionLost:
        return .connectionFailed("No internet connection", innerError: self)
      case .timedOut:
        return .connectionFailed("Connection timeout", innerError: self)
      case .cannotFindHost, .cannotConnectToHost:
        return .dataCenterNotResponding("Cannot reach server", innerError: self)
      case .cancelled:
        return .operationCancelled("Request cancelled", innerError: self)
      default:
        return .connectionFailed(urlError.localizedDescription, innerError: self)
      }
    }
    return .connectionFailed(self.localizedDescription, innerError: self)
  }

  func toProtocolFailure() -> ProtocolFailure {
    .generic(self.localizedDescription, innerError: self)
  }

  func toAuthenticationFailure() -> AuthenticationFailure {
    .unexpectedError(self.localizedDescription, innerError: self)
  }

  func toCryptographyFailure() -> CryptographyFailure {
    .initializationFailed(self.localizedDescription, innerError: self)
  }

  func toLogoutFailure() -> LogoutFailure {
    .unexpectedError(self.localizedDescription, innerError: self)
  }
}
