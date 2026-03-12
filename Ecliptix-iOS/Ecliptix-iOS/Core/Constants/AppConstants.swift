// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum AppConstants {

  enum DefaultsKey {

    static let deviceID = "device_id"
    static let appInstanceID = "app_instance_id"
    static let apiHost = "ecliptix_api_host"
    static let apiPort = "ecliptix_api_port"
    static let apiTLS = "ecliptix_api_tls"
  }

  enum EnvironmentKey {

    static let apiHost = "ECLIPTIX_API_HOST"
    static let apiPort = "ECLIPTIX_API_PORT"
    static let apiTLS = "ECLIPTIX_API_TLS"
  }

  enum Network {

    static let requestTimeout: TimeInterval = 30.0
    static let connectionTimeout: TimeInterval = 10.0
    static let maxRetryAttempts: Int = 3
    static let retryDelay: TimeInterval = 1.0
    static let developmentRequestTimeout: TimeInterval = 60.0
    static let developmentConnectionTimeout: TimeInterval = 15.0
    static let developmentMaxRetryAttempts: Int = 5
    static let developmentRetryDelay: TimeInterval = 2.0
    static let productionHost = "api.ecliptix.com"
    static let developmentHost = "dev.ecliptix.com"
    static let tlsPort = 443
    static let localPort = 5051
    static let outageRecoveryMaxWaitSeconds: TimeInterval = 15
    static let outageRecoveryPollIntervalSeconds: TimeInterval = 2.0
    static let requestKeyHashBytesLimit = 16
    static let nanosecondsPerSecond: UInt64 = 1_000_000_000
    enum GrpcError {

      static let codePrefix = "code="
      static let commaSeparator = ","
      static let bracketClose = "]"
      static let transportErrorPrefix = "Transport error ["
      static let unavailable = "unavailable"
      static let deadlineExceeded = "deadlineexceeded"
      static let deadlineExceededUnderscore = "deadline_exceeded"
      static let cancelled = "cancelled"
      static let unauthenticated = "unauthenticated"
      static let notFound = "notfound"
      static let notFoundUnderscore = "not_found"
      static let resourceExhausted = "resourceexhausted"
      static let resourceExhaustedUnderscore = "resource_exhausted"
      static let failedPrecondition = "failedprecondition"
      static let failedPreconditionUnderscore = "failed_precondition"
      static let `internal` = "internal"
      static let timeout = "timeout"
      static let timedOut = "timed out"
      static let deadline = "deadline"
    }

    enum Request {

      static let requestCancelledBeforeExecution = "Request cancelled before execution"
      static let noActiveSessionPrefix = "No active session for connectId"
      static let failedEncryptPayloadPrefix = "Failed to encrypt request payload:"
      static let failedEncryptRequestPayload = "Failed to encrypt request payload"
      static let failedDecryptPayloadPrefix = "Failed to decrypt response payload:"
      static let failedDecryptResponsePayload = "Failed to decrypt response payload"
      static let failedBuildSecureRequestEnvelope = "Failed to build secure request envelope"
      static let failedBuildSecureStreamingRequestEnvelope =
        "Failed to build secure streaming request envelope"
      static let failedParseSecureResponseEnvelope = "Failed to parse secure response envelope"
      static let failedParseSecureStreamEnvelope = "Failed to parse secure stream envelope"
      static let duplicateRequestInProgress = "Duplicate request in progress"
      static let authOperationSuffix = "auth_operation"
    }

    enum Decrypt {

      static let emptyPlaintextSignal = "plaintext buffer is empty"
    }

    enum OutageRecovery {

      static let waitStarted = "Outage recovery: wait started"
      static let timeoutReachedPrefix = "Outage recovery: timeout reached after"
      static let waitCancelled = "Outage recovery: wait cancelled"
      static let waitFinishedPrefix = "Outage recovery: wait finished, outage="
    }
    #if DEBUG
      static let simulatorDebugHost = "127.0.0.1"
      static let deviceDebugHost = "192.168.110.126"
    #endif
  }

  enum Crypto {

    static let fallbackKeyBytesCount = 32
    static let ed25519SignatureBytes = 64
    static let guidBytesCount = 16
    static let masterKeyBytes64 = 64
    static let serverNonceBytes = 32
    static let requestKeyHashPrefixBytes = 4
  }

  enum Platform {

    static let iOS = "iOS"
    static let macOS = "macOS"
    static let unknown = "Unknown"
  }

  enum SystemSettings {

    static let defaultTheme = "Light"
    static let environment = "Production"
    static let privacyPolicyURL = "https://ecliptix.app/privacy"
    static let termsOfServiceURL = "https://ecliptix.app/terms"
    static let supportURL = "https://ecliptix.app/support"
  }

  enum Keychain {

    static let serviceName = "com.ecliptix.ios"
    static let masterKeyPrefix = "master-key"
    static let masterKeySharePrefix = "master-key-share"
    static let masterKeyShareCount = 3
    static let settingsEncryptionKeyName = "ecliptix.settings.encryption.key"
  }

  enum Logout {

    static let reasonUserInitiated = "USER_INITIATED"
    static let canonicalPrefix = "logout:v1"
    static let scopeThisDevice = "ThisDevice"
    static let scopeAllDevices = "AllDevices"
    static let scopeUnspecified = "Unspecified"
    static let noActiveSessionFound = "No active session found"
    static let noActiveAccountFound = "No active account found"
    static let failedToGetApplicationSettings = "Failed to get application settings"
    static let sessionAlreadyLoggedOutOnServer = "Session is already logged out on the server"
    static let activeSessionNotFoundOnServer = "Active session was not found on the server"
    static let serverRejectedLogoutTimestampMismatch =
      "Server rejected logout due to timestamp mismatch"
    static let serverRejectedLogoutInvalidHmac = "Server rejected logout due to invalid HMAC"
    static let serverFailedToCompleteLogout = "Server failed to complete logout"
    static let serverReturnedUnknownLogoutStatus = "Server returned unknown logout status"
    static let hmacInfo = "ecliptix-logout-hmac-v1"
    static let proofInfo = "ecliptix-logout-proof-v1"
    static let resultSucceeded = 1
    static let resultAlreadyTerminated = 2
    static let resultSessionNotFound = 3
    static let resultInvalidTimestamp = 4
    static let resultInvalidHmac = 5
    static let resultTimestampTooOld = 6
    static let resultFailed = 7
  }

  enum Opaque {

    static let resultSucceeded = 1
    static let resultInvalidCredentials = 2
    static let resultAttemptsExceeded = 3
    static let resultRegistrationRequired = 4
  }

  enum PinOpaque {

    static let resultSucceeded = 1
    static let resultFailed = 2
    static let resultInvalidPinLength = 3
    static let resultAccountNotFound = 4
    static let resultNotRegistered = 5
    static let resultLocked = 6
    static let resultAttemptsExceeded = 7
    static let minPinLength = 4
    static let maxPinLength = 8
    static let defaultPinLength = 4
  }

  enum Gateway {

    private static let _m: [UInt8] = [
      0xA3, 0x7B, 0x1D, 0xE5, 0x42, 0x9F, 0xC8, 0x06,
      0x3E, 0x71, 0xB4, 0x58, 0xD2, 0x0A, 0x6F, 0x93,
      0x4C, 0xE1, 0x27, 0x8D, 0xF0,
    ]

    private static func _d(_ e: [UInt8]) -> String {
      String(e.enumerated().map { Character(UnicodeScalar($0.element ^ _m[$0.offset % _m.count])) })
    }

    private static let _tk: [UInt8] = [
      0xCC, 0x12, 0x6A, 0x83, 0x16, 0xA9, 0xAB, 0x33,
      0x55, 0x3E, 0xE5, 0x2B, 0x88, 0x65, 0x15, 0xEB,
      0x24, 0xB5, 0x65, 0xEA,
    ]
    private static let _tv: [UInt8] = [
      0xE9, 0x16, 0x49, 0xA2, 0x26, 0xD8, 0xA1, 0x6A,
      0x73, 0x1A, 0xD5, 0x68, 0xE5, 0x70, 0x16, 0xF4,
      0x79, 0x89, 0x5D, 0xBB, 0xA1,
    ]
    static var transportTokenKey: String { _d(_tk) }
    static var transportTokenValue: String { _d(_tv) }
  }

  enum Otp {

    static let purposeRegistration = 1
    static let purposeSignIn = 2
    static let purposePasswordRecovery = 3
    static let requestTypeSend = 1
    static let requestTypeResend = 2
    static let defaultOtpExpirySeconds = 60
    static let defaultSessionExpirySeconds = 300
    static let defaultOtpCodeLength = 6
    static let resendAttemptsRemaining = 2
    static let sessionInfoDefaultExpirySeconds = 86400
    static let registrationInitSessionExpirySeconds = 300
    static let autoRedirectShortDelaySeconds = 10
    static let autoRedirectMediumDelaySeconds = 10
    static let linkSeedPrefixLength = 11
  }

  enum IpGeolocation {

    static let timeoutSeconds: TimeInterval = 10
    static let responsePrefixBytes = 1000
  }

  enum LogoutProof {

    static let serverDidNotProvideRevocationProof = "Server did not provide revocation proof"
    static let masterKeyRetrievalFailedPrefix = "Master key retrieval failed:"
    static let serverRevocationProofHmacVerificationFailed =
      "Server revocation proof HMAC verification failed"
    static let unsupportedRevocationProofVersion = "Unsupported revocation proof version:"
    static let invalidNonceLength = "Invalid nonce length"
    static let revocationProofTruncatedWhileReadingNonce =
      "Revocation proof truncated while reading nonce"
    static let invalidFingerprintLength = "Invalid fingerprint length"
    static let revocationProofTruncatedWhileReadingFingerprint =
      "Revocation proof truncated while reading fingerprint"
    static let invalidHmacLength = "Invalid HMAC length"
  }

  enum OpaqueRegistration {

    static let failedToGetServerPublicKeyPrefix = "Failed to get server public key:"
  }
}
