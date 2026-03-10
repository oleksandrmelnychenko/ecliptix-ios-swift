// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
enum ServerErrorCode {

  enum Error {
    static let `internal` = "error.internal"
    static let grpc = "error.grpc"
    static let alreadyExists = "error.already_exists"
    static let rateLimitDb = "error.rate_limit_db"
    static let flowCreate = "error.flow_create"
    static let flowFetch = "error.flow_fetch"
    static let otpCreate = "error.otp_create"
    static let smsDelivery = "error.sms_delivery"
  }

  enum Otp {
    static let initiated = "otp.initiated"
    static let resent = "otp.resent"
    static let verified = "otp.verified"
    static let invalidPayload = "otp.invalid_payload"
    static let invalidCode = "otp.invalid_code"
    static let sessionNotFound = "otp.session_not_found"
    static let expired = "otp.expired"
    static let codeExpired = "otp.code_expired"
    static let notFound = "otp.not_found"
    static let tooManyAttempts = "otp.too_many_attempts"
    static let rateLimited = "otp.rate_limited"
    static let countdown = "otp.countdown"
    static let resendCooldown = "otp.resend_cooldown"
    static let recoveryInvalidPayload = "otp.recovery_invalid_payload"
  }

  enum Mobile {
    static let valid = "mobile.valid"
    static let invalid = "mobile.invalid"
    static let invalidPayload = "mobile.invalid_payload"
    static let dbError = "mobile.db_error"
    static let cannotBeEmpty = "mobile.cannot_be_empty"
    static let parsingInvalidCountryCode = "mobile.parsing_invalid_country_code"
    static let parsingInvalidNumber = "mobile.parsing_invalid_number"
    static let parsingTooShort = "mobile.parsing_too_short"
    static let parsingTooLong = "mobile.parsing_too_long"
    static let validationUnexpectedError = "mobile.validation_unexpected_error"
    static let availabilityChecked = "mobile.availability_checked"
    static let numberAvailable = "mobile.number_available"
    static let numberTakenActive = "mobile.number_taken_active"
    static let numberTakenInactive = "mobile.number_taken_inactive"
    static let numberBlocked = "mobile.number_blocked"
    static let availabilityCheckError = "mobile.availability_check_error"
    static let dataCorruptionDetected = "mobile.data_corruption_detected"
    static let registrationExpired = "mobile.registration_expired"
    static let incompleteRegistrationContinue = "mobile.incomplete_registration_continue"
    static let incompleteRegistrationDifferentDevice =
      "mobile.incomplete_registration_different_device"
  }

  enum Phone {
    static let cannotBeEmpty = "phone.cannot_be_empty"
    static let parsingInvalidCountryCode = "phone.parsing_invalid_country_code"
    static let parsingInvalidNumber = "phone.parsing_invalid_number"
    static let parsingTooShort = "phone.parsing_too_short"
    static let parsingTooLong = "phone.parsing_too_long"
    static let validationUnexpectedError = "phone.validation_unexpected_error"
  }

  enum Session {
    static let handshake = "session.handshake"
    static let recovery = "session.recovery"
    static let authHandshake = "session.auth_handshake"
    static let logout = "session.logout"
    static let logoutAnonymous = "session.logout_anonymous"
    static let serverKeys = "session.server_keys"
    static let invalidHmac = "session.invalid_hmac"
    static let invalidIdentityProof = "session.invalid_identity_proof"
    static let keyUnavailable = "session.key_unavailable"
    static let reinitRequired = "session.reinit_required"
  }

  enum Device {
    static let registered = "device.registered"
  }

  enum Opaque {
    static let registrationInit = "opaque.registration_init"
    static let registrationComplete = "opaque.registration_complete"
    static let signinInit = "opaque.signin_init"
    static let signinFinalize = "opaque.signin_finalize"
    static let recoveryInit = "opaque.recovery_init"
    static let recoveryComplete = "opaque.recovery_complete"
    static let invalidInput = "opaque.error.invalid_input"
    static let cryptoError = "opaque.error.crypto"
    static let invalidProtocolMessage = "opaque.error.invalid_protocol_message"
    static let validationError = "opaque.error.validation"
    static let authenticationError = "opaque.error.authentication"
    static let invalidPublicKey = "opaque.error.invalid_public_key"
    static let alreadyRegistered = "opaque.error.already_registered"
    static let invalidKemInput = "opaque.error.invalid_kem_input"
    static let invalidEnvelope = "opaque.error.invalid_envelope"
  }

  enum Recovery {

    static let sessionCreated = "recovery.session_created"
    static let sessionStatus = "recovery.session_status"
    static let sessionCancelled = "recovery.session_cancelled"
    static let factorVerified = "recovery.factor_verified"
    static let codesGenerated = "recovery.codes_generated"
    static let codesStatus = "recovery.codes_status"
    static let codeVerified = "recovery.code_verified"
    static let codeInvalid = "recovery.code_invalid"
    static let codeExhausted = "recovery.code_exhausted"
    static let invalidCombination = "recovery.invalid_combination"
    static let coolingPeriod = "recovery.cooling_period"
    static let rateLimited = "recovery.rate_limited"
    static let activityLog = "recovery.activity_log"
    static let trustedDeviceRequested = "recovery.trusted_device_requested"
    static let trustedDeviceDecided = "recovery.trusted_device_decided"
    static let noTrustedDevices = "recovery.no_trusted_devices"
  }

  enum Pin {

    static let register = "pin.register"
    static let verify = "pin.verify"
    static let disable = "pin.disable"
    static let invalidAccount = "pin.invalid_account"
    static let invalidLength = "pin.invalid_length"
    static let invalidPin = "pin.invalid_pin"
    static let locked = "pin.locked"
    static let notRegistered = "pin.not_registered"
  }

  enum Profile {
    static let nameChecked = "profile.name_checked"
    static let upserted = "profile.upserted"
    static let upsertFailed = "profile.upsert_failed"
    static let found = "profile.found"
    static let notFound = "profile.not_found"
  }

  enum PhoneChange {
    static let initiated = "phone_change.initiated"
    static let oldVerified = "phone_change.old_verified"
    static let newVerified = "phone_change.new_verified"
    static let status = "phone_change.status"
    static let cancelled = "phone_change.cancelled"
    static let invalidSession = "phone_change.invalid_session"
    static let alreadyInProgress = "phone_change.already_in_progress"
    static let recoveryNotReady = "phone_change.recovery_not_ready"
    static let numberBlocked = "phone_change.number_blocked"
  }

  enum Verification {
    static let storageUnavailable = "verification.storage_unavailable"
    static let sessionStarted = "verification.session_started"
    static let otpResent = "verification.otp_resent"
  }

  enum Messaging {
    static let chatUnavailable = "messaging.chat_unavailable"
    static let streamConnected = "messaging.stream_connected"
  }

  enum Streaming {
    static let unavailable = "streaming.unavailable"
  }

  enum Gateway {
    static let passthrough = "gateway.passthrough"
    static let decodeError = "gateway.decode_error"
    static let emptyClientStream = "gateway.empty_client_stream"
    static let emptyBidiStream = "gateway.empty_bidi_stream"
  }

  enum RateLimit {
    static let ok = "rate_limit.ok"
    static let mobileFlowExceeded = "rate_limit.mobile_flow_exceeded"
    static let deviceFlowExceeded = "rate_limit.device_flow_exceeded"
    static let passwordRecoveryMobileExceeded = "rate_limit.password_recovery_mobile_exceeded"
    static let passwordRecoveryDeviceExceeded = "rate_limit.password_recovery_device_exceeded"
    static let otpSendsPerFlowExceeded = "rate_limit.otp_sends_per_flow_exceeded"
    static let otpSendsPerMobileExceeded = "rate_limit.otp_sends_per_mobile_exceeded"
  }

  enum Auth {
    static let signinRateLimited = "auth.signin_rate_limited"
    static let recoveryRateLimited = "auth.recovery_rate_limited"
    static let accountLocked = "auth.account_locked"
    static let accountLockedEscalated = "auth.account_locked_escalated"
  }

  enum Validation {
    static let missingMetadata = "validation.missing_metadata"
    static let missingIdentity = "validation.missing_identity"
    static let invalidEventType = "validation.invalid_event_type"
    static let unknownEventType = "validation.unknown_event_type"
    static let invalidDeliveryKind = "validation.invalid_delivery_kind"
    static let missingEventId = "validation.missing_event_id"
    static let missingPartitionKey = "validation.missing_partition_key"
    static let fieldTooLong = "validation.field_too_long"
    static let invalidIdempotencyKey = "validation.invalid_idempotency_key"
    static let invalidApplicationInstanceId = "validation.invalid_application_instance_id"
    static let invalidDeviceId = "validation.invalid_device_id"
    static let payloadTooLarge = "validation.payload_too_large"
    static let missingTimestamp = "validation.missing_timestamp"
    static let timestampDriftExceeded = "validation.timestamp_drift_exceeded"
  }
}
