// Copyright (c) 2026 Oleksandr Melnychenko. All rights reserved.
// SPDX-License-Identifier: MIT
import Foundation

enum EPPNative {

  enum EppErrorCode: Int32 {
    case success = 0
    case errorGeneric = 1
    case errorInvalidInput = 2
    case errorKeyGeneration = 3
    case errorDeriveKey = 4
    case errorHandshake = 5
    case errorEncryption = 6
    case errorDecryption = 7
    case errorDecode = 8
    case errorEncode = 9
    case errorBufferTooSmall = 10
    case errorObjectDisposed = 11
    case errorPrepareLocal = 12
    case errorOutOfMemory = 13
    case errorCryptoFailure = 14
    case errorNullPointer = 15
    case errorInvalidState = 16
    case errorReplayAttack = 17
    case errorSessionExpired = 18
    case errorPqMissing = 19
    case errorGroupProtocol = 20
    case errorGroupMembership = 21
    case errorTreeIntegrity = 22
    case errorWelcome = 23
    case errorMessageExpired = 24
    case errorFranking = 25
  }

  enum EppEnvelopeType: Int32 {
    case request = 0
    case response = 1
    case notification = 2
    case heartbeat = 3
    case errorResponse = 4
  }

  struct EppBuffer {

    let data: UnsafeMutablePointer<UInt8>?
    let length: Int
  }

  struct EppSessionConfig {

    let maxMessagesPerChain: UInt32
  }

  struct EppGroupSecurityPolicy {

    var maxMessagesPerEpoch: UInt32
    var maxSkippedKeysPerSender: UInt32
    var blockExternalJoin: UInt8
    var enhancedKeySchedule: UInt8
    var mandatoryFranking: UInt8

    init(
      maxMessagesPerEpoch: UInt32 = 0,
      maxSkippedKeysPerSender: UInt32 = 0,
      blockExternalJoin: UInt8 = 0,
      enhancedKeySchedule: UInt8 = 0,
      mandatoryFranking: UInt8 = 0
    ) {
      self.maxMessagesPerEpoch = maxMessagesPerEpoch
      self.maxSkippedKeysPerSender = maxSkippedKeysPerSender
      self.blockExternalJoin = blockExternalJoin
      self.enhancedKeySchedule = enhancedKeySchedule
      self.mandatoryFranking = mandatoryFranking
    }
  }

  struct EppGroupDecryptResult {

    var plaintext: EppBuffer
    var senderLeafIndex: UInt32
    var generation: UInt32
    var contentType: UInt32
    var ttlSeconds: UInt32
    var sentTimestamp: UInt64
    var messageId: EppBuffer
    var referencedMessageId: EppBuffer
    var hasSealedPayload: UInt8
    var hasFrankingData: UInt8

    init() {
      plaintext = EppBuffer(data: nil, length: 0)
      senderLeafIndex = 0
      generation = 0
      contentType = 0
      ttlSeconds = 0
      sentTimestamp = 0
      messageId = EppBuffer(data: nil, length: 0)
      referencedMessageId = EppBuffer(data: nil, length: 0)
      hasSealedPayload = 0
      hasFrankingData = 0
    }
  }

  struct EppSessionPeerIdentity {

    var ed25519Public:
      (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
      )
    var x25519Public:
      (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
      )

    init() {
      ed25519Public = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0
      )
      x25519Public = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0
      )
    }
  }

  struct EppEnvelopeMetadata {

    var envelopeType: Int32
    var envelopeId: UInt32
    var messageIndex: UInt64
    var correlationId: UnsafeMutablePointer<CChar>?
    var correlationIdLength: Int

    init() {
      envelopeType = 0
      envelopeId = 0
      messageIndex = 0
      correlationId = nil
      correlationIdLength = 0
    }
  }
  typealias EppHandle = UnsafeMutableRawPointer
  @_silgen_name("epp_version")
  static func version() -> UnsafePointer<CChar>
  @_silgen_name("epp_init")
  static func initialize() -> Int32
  @_silgen_name("epp_shutdown")
  static func shutdown()
  @_silgen_name("epp_identity_create")
  static func identityCreate(
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_create_from_seed")
  static func identityCreateFromSeed(
    _ seed: UnsafePointer<UInt8>,
    _ seedLength: Int,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_create_with_context")
  static func identityCreateWithContext(
    _ seed: UnsafePointer<UInt8>,
    _ seedLength: Int,
    _ membershipId: UnsafePointer<CChar>,
    _ membershipIdLength: Int,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_get_x25519_public")
  static func identityGetX25519Public(
    _ handle: EppHandle,
    _ outKey: UnsafeMutablePointer<UInt8>,
    _ outKeyLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_get_ed25519_public")
  static func identityGetEd25519Public(
    _ handle: EppHandle,
    _ outKey: UnsafeMutablePointer<UInt8>,
    _ outKeyLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_get_kyber_public")
  static func identityGetKyberPublic(
    _ handle: EppHandle,
    _ outKey: UnsafeMutablePointer<UInt8>,
    _ outKeyLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_identity_destroy")
  static func identityDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_prekey_bundle_create")
  static func prekeyBundleCreate(
    _ identityHandle: EppHandle,
    _ outBundle: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_prekey_bundle_replenish")
  static func prekeyBundleReplenish(
    _ identityHandle: EppHandle,
    _ count: UInt32,
    _ outKeys: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_handshake_initiator_start")
  static func handshakeInitiatorStart(
    _ identityHandle: EppHandle,
    _ peerPrekeyBundle: UnsafePointer<UInt8>,
    _ peerPrekeyBundleLength: Int,
    _ config: UnsafePointer<EppSessionConfig>,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outHandshakeInit: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_handshake_initiator_finish")
  static func handshakeInitiatorFinish(
    _ handle: EppHandle,
    _ handshakeAck: UnsafePointer<UInt8>,
    _ handshakeAckLength: Int,
    _ outSession: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_handshake_initiator_destroy")
  static func handshakeInitiatorDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_handshake_responder_start")
  static func handshakeResponderStart(
    _ identityHandle: EppHandle,
    _ localPrekeyBundle: UnsafePointer<UInt8>,
    _ localPrekeyBundleLength: Int,
    _ handshakeInit: UnsafePointer<UInt8>,
    _ handshakeInitLength: Int,
    _ config: UnsafePointer<EppSessionConfig>?,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outHandshakeAck: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_handshake_responder_finish")
  static func handshakeResponderFinish(
    _ handle: EppHandle,
    _ outSession: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_handshake_responder_destroy")
  static func handshakeResponderDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_session_encrypt")
  static func sessionEncrypt(
    _ handle: EppHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLength: Int,
    _ envelopeType: Int32,
    _ envelopeId: UInt32,
    _ correlationId: UnsafePointer<UInt8>?,
    _ correlationIdLength: Int,
    _ outEncryptedEnvelope: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_decrypt")
  static func sessionDecrypt(
    _ handle: EppHandle,
    _ encryptedEnvelope: UnsafePointer<UInt8>,
    _ encryptedEnvelopeLength: Int,
    _ outPlaintext: UnsafeMutablePointer<EppBuffer>,
    _ outMetadata: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_destroy")
  static func sessionDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_session_nonce_remaining")
  static func sessionNonceRemaining(
    _ handle: EppHandle,
    _ outRemaining: UnsafeMutablePointer<UInt64>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_get_id")
  static func sessionGetId(
    _ handle: EppHandle,
    _ outSessionId: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_get_peer_identity")
  static func sessionGetPeerIdentity(
    _ handle: EppHandle,
    _ outIdentity: UnsafeMutablePointer<EppSessionPeerIdentity>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_get_local_identity")
  static func sessionGetLocalIdentity(
    _ handle: EppHandle,
    _ outIdentity: UnsafeMutablePointer<EppSessionPeerIdentity>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_envelope_metadata_parse")
  static func envelopeMetadataParse(
    _ metadataBytes: UnsafePointer<UInt8>,
    _ metadataLength: Int,
    _ outMeta: UnsafeMutablePointer<EppEnvelopeMetadata>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_envelope_metadata_free")
  static func envelopeMetadataFree(_ meta: UnsafeMutablePointer<EppEnvelopeMetadata>)
  @_silgen_name("epp_envelope_validate")
  static func envelopeValidate(
    _ encryptedEnvelope: UnsafePointer<UInt8>,
    _ encryptedEnvelopeLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_shamir_split")
  static func shamirSplit(
    _ secret: UnsafePointer<UInt8>,
    _ secretLength: Int,
    _ threshold: UInt8,
    _ shareCount: UInt8,
    _ authKey: UnsafePointer<UInt8>?,
    _ authKeyLength: Int,
    _ outShares: UnsafeMutablePointer<EppBuffer>,
    _ outShareLength: UnsafeMutablePointer<Int>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_shamir_reconstruct")
  static func shamirReconstruct(
    _ shares: UnsafePointer<UInt8>,
    _ sharesLength: Int,
    _ shareLength: Int,
    _ shareCount: Int,
    _ authKey: UnsafePointer<UInt8>?,
    _ authKeyLength: Int,
    _ outSecret: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_buffer_release")
  static func bufferRelease(_ buffer: UnsafeMutablePointer<EppBuffer>)
  @_silgen_name("epp_buffer_alloc")
  static func bufferAlloc(_ capacity: Int) -> UnsafeMutableRawPointer?
  @_silgen_name("epp_buffer_free")
  static func bufferFree(_ buffer: UnsafeMutableRawPointer)
  @_silgen_name("epp_secure_wipe")
  static func secureWipe(_ data: UnsafeMutableRawPointer, _ length: Int) -> Int32
  @_silgen_name("epp_derive_root_key")
  static func deriveRootKey(
    _ opaqueSessionKey: UnsafePointer<UInt8>,
    _ opaqueSessionKeyLength: Int,
    _ userContext: UnsafePointer<UInt8>,
    _ userContextLength: Int,
    _ outRootKey: UnsafeMutablePointer<UInt8>,
    _ outRootKeyLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_error_free")
  static func errorFree(_ error: UnsafeMutableRawPointer)
  @_silgen_name("epp_error_string")
  static func errorString(_ code: Int32) -> UnsafePointer<CChar>
  @_silgen_name("epp_group_generate_key_package")
  static func groupGenerateKeyPackage(
    _ identityHandle: EppHandle,
    _ credential: UnsafePointer<UInt8>,
    _ credentialLength: Int,
    _ outKeyPackage: UnsafeMutablePointer<EppBuffer>,
    _ outSecrets: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_key_package_secrets_destroy")
  static func groupKeyPackageSecretsDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_group_create")
  static func groupCreate(
    _ identityHandle: EppHandle,
    _ credential: UnsafePointer<UInt8>,
    _ credentialLength: Int,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_create_shielded")
  static func groupCreateShielded(
    _ identityHandle: EppHandle,
    _ credential: UnsafePointer<UInt8>,
    _ credentialLength: Int,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_create_with_policy")
  static func groupCreateWithPolicy(
    _ identityHandle: EppHandle,
    _ credential: UnsafePointer<UInt8>,
    _ credentialLength: Int,
    _ policy: UnsafePointer<EppGroupSecurityPolicy>,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_get_security_policy")
  static func groupGetSecurityPolicy(
    _ handle: EppHandle,
    _ outPolicy: UnsafeMutablePointer<EppGroupSecurityPolicy>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_is_shielded")
  static func groupIsShielded(
    _ handle: EppHandle,
    _ outShielded: UnsafeMutablePointer<UInt8>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_join")
  static func groupJoin(
    _ identityHandle: EppHandle,
    _ welcomeBytes: UnsafePointer<UInt8>,
    _ welcomeLength: Int,
    _ secretsHandle: EppHandle,
    _ outGroupHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_add_member")
  static func groupAddMember(
    _ handle: EppHandle,
    _ keyPackageBytes: UnsafePointer<UInt8>,
    _ keyPackageLength: Int,
    _ outCommit: UnsafeMutablePointer<EppBuffer>,
    _ outWelcome: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_remove_member")
  static func groupRemoveMember(
    _ handle: EppHandle,
    _ leafIndex: UInt32,
    _ outCommit: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_update")
  static func groupUpdate(
    _ handle: EppHandle,
    _ outCommit: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_process_commit")
  static func groupProcessCommit(
    _ handle: EppHandle,
    _ commitBytes: UnsafePointer<UInt8>,
    _ commitLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_encrypt")
  static func groupEncrypt(
    _ handle: EppHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLength: Int,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_decrypt")
  static func groupDecrypt(
    _ handle: EppHandle,
    _ ciphertext: UnsafePointer<UInt8>,
    _ ciphertextLength: Int,
    _ outPlaintext: UnsafeMutablePointer<EppBuffer>,
    _ outSenderLeaf: UnsafeMutablePointer<UInt32>,
    _ outGeneration: UnsafeMutablePointer<UInt32>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_get_id")
  static func groupGetId(
    _ handle: EppHandle,
    _ outGroupId: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_get_epoch")
  static func groupGetEpoch(_ handle: EppHandle) -> UInt64
  @_silgen_name("epp_group_get_my_leaf_index")
  static func groupGetMyLeafIndex(_ handle: EppHandle) -> UInt32
  @_silgen_name("epp_group_get_member_count")
  static func groupGetMemberCount(_ handle: EppHandle) -> UInt32
  @_silgen_name("epp_group_serialize")
  static func groupSerialize(
    _ handle: EppHandle,
    _ key: UnsafePointer<UInt8>,
    _ keyLength: Int,
    _ externalCounter: UInt64,
    _ outState: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_deserialize")
  static func groupDeserialize(
    _ stateBytes: UnsafePointer<UInt8>,
    _ stateLength: Int,
    _ key: UnsafePointer<UInt8>,
    _ keyLength: Int,
    _ minExternalCounter: UInt64,
    _ outExternalCounter: UnsafeMutablePointer<UInt64>,
    _ identityHandle: EppHandle,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_export_public_state")
  static func groupExportPublicState(
    _ handle: EppHandle,
    _ outPublicState: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_join_external")
  static func groupJoinExternal(
    _ identityHandle: EppHandle,
    _ publicState: UnsafePointer<UInt8>,
    _ publicStateLength: Int,
    _ credential: UnsafePointer<UInt8>,
    _ credentialLength: Int,
    _ outGroupHandle: UnsafeMutablePointer<EppHandle?>,
    _ outCommit: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_get_member_leaf_indices")
  static func groupGetMemberLeafIndices(
    _ handle: EppHandle,
    _ outIndices: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_destroy")
  static func groupDestroy(_ handle: UnsafeMutablePointer<EppHandle?>)
  @_silgen_name("epp_group_encrypt_sealed")
  static func groupEncryptSealed(
    _ handle: EppHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLength: Int,
    _ hint: UnsafePointer<UInt8>,
    _ hintLength: Int,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_encrypt_disappearing")
  static func groupEncryptDisappearing(
    _ handle: EppHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLength: Int,
    _ ttlSeconds: UInt32,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_encrypt_frankable")
  static func groupEncryptFrankable(
    _ handle: EppHandle,
    _ plaintext: UnsafePointer<UInt8>,
    _ plaintextLength: Int,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_reveal_sealed")
  static func groupRevealSealed(
    _ hint: UnsafePointer<UInt8>,
    _ hintLength: Int,
    _ encryptedContent: UnsafePointer<UInt8>,
    _ encryptedContentLength: Int,
    _ nonce: UnsafePointer<UInt8>,
    _ nonceLength: Int,
    _ sealKey: UnsafePointer<UInt8>,
    _ sealKeyLength: Int,
    _ outPlaintext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_verify_franking")
  static func groupVerifyFranking(
    _ frankingTag: UnsafePointer<UInt8>,
    _ frankingTagLength: Int,
    _ frankingKey: UnsafePointer<UInt8>,
    _ frankingKeyLength: Int,
    _ content: UnsafePointer<UInt8>,
    _ contentLength: Int,
    _ sealedContent: UnsafePointer<UInt8>?,
    _ sealedContentLength: Int,
    _ outValid: UnsafeMutablePointer<UInt8>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_decrypt_ex")
  static func groupDecryptEx(
    _ handle: EppHandle,
    _ ciphertext: UnsafePointer<UInt8>,
    _ ciphertextLength: Int,
    _ outResult: UnsafeMutablePointer<EppGroupDecryptResult>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_decrypt_result_free")
  static func groupDecryptResultFree(_ result: UnsafeMutablePointer<EppGroupDecryptResult>)
  @_silgen_name("epp_group_compute_message_id")
  static func groupComputeMessageId(
    _ groupId: UnsafePointer<UInt8>,
    _ groupIdLength: Int,
    _ epoch: UInt64,
    _ senderLeafIndex: UInt32,
    _ generation: UInt32,
    _ outMessageId: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_encrypt_edit")
  static func groupEncryptEdit(
    _ handle: EppHandle,
    _ newContent: UnsafePointer<UInt8>,
    _ newContentLength: Int,
    _ targetMessageId: UnsafePointer<UInt8>,
    _ targetMessageIdLength: Int,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_encrypt_delete")
  static func groupEncryptDelete(
    _ handle: EppHandle,
    _ targetMessageId: UnsafePointer<UInt8>,
    _ targetMessageIdLength: Int,
    _ outCiphertext: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_set_psk")
  static func groupSetPsk(
    _ handle: EppHandle,
    _ pskId: UnsafePointer<UInt8>,
    _ pskIdLength: Int,
    _ psk: UnsafePointer<UInt8>,
    _ pskLength: Int,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_group_get_pending_reinit")
  static func groupGetPendingReinit(
    _ handle: EppHandle,
    _ outNewGroupId: UnsafeMutablePointer<EppBuffer>,
    _ outNewVersion: UnsafeMutablePointer<UInt32>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_serialize_sealed")
  static func sessionSerializeSealed(
    _ handle: EppHandle,
    _ key: UnsafePointer<UInt8>,
    _ keyLength: Int,
    _ externalCounter: UInt64,
    _ outState: UnsafeMutablePointer<EppBuffer>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32
  @_silgen_name("epp_session_deserialize_sealed")
  static func sessionDeserializeSealed(
    _ stateBytes: UnsafePointer<UInt8>,
    _ stateLength: Int,
    _ key: UnsafePointer<UInt8>,
    _ keyLength: Int,
    _ minExternalCounter: UInt64,
    _ outExternalCounter: UnsafeMutablePointer<UInt64>,
    _ outHandle: UnsafeMutablePointer<EppHandle?>,
    _ outError: UnsafeMutablePointer<EppErrorCode>
  ) -> Int32

  static func getVersion() -> String {
    let cString: UnsafePointer<CChar> = version()
    return String(cString: cString)
  }

  static func errorCodeToString(_ code: EppErrorCode) -> String {
    switch code {
    case .success:
      return "Success"
    case .errorGeneric:
      return "Generic error"
    case .errorInvalidInput:
      return "Invalid input"
    case .errorKeyGeneration:
      return "Key generation failed"
    case .errorDeriveKey:
      return "Key derivation failed"
    case .errorHandshake:
      return "Handshake failed"
    case .errorEncryption:
      return "Encryption failed"
    case .errorDecryption:
      return "Decryption failed"
    case .errorDecode:
      return "Decoding failed"
    case .errorEncode:
      return "Encoding failed"
    case .errorBufferTooSmall:
      return "Buffer too small"
    case .errorObjectDisposed:
      return "Object already disposed"
    case .errorPrepareLocal:
      return "Failed to prepare local state"
    case .errorOutOfMemory:
      return "Out of memory"
    case .errorCryptoFailure:
      return "Cryptography failure"
    case .errorNullPointer:
      return "Null pointer"
    case .errorInvalidState:
      return "Invalid state"
    case .errorReplayAttack:
      return "Replay attack detected"
    case .errorSessionExpired:
      return "Session expired"
    case .errorPqMissing:
      return "Post-quantum keys missing"
    case .errorGroupProtocol:
      return "Group protocol error"
    case .errorGroupMembership:
      return "Group membership error"
    case .errorTreeIntegrity:
      return "Tree integrity error"
    case .errorWelcome:
      return "Welcome processing error"
    case .errorMessageExpired:
      return "Message expired"
    case .errorFranking:
      return "Franking verification failed"
    }
  }
}

enum ProtocolError: Error {
  case invalidInput(String)
  case keyGenerationFailed(String)
  case deriveKeyFailed(String)
  case handshakeFailed(String)
  case encryptionFailed(String)
  case decryptionFailed(String)
  case decodeFailed(String)
  case encodeFailed(String)
  case bufferTooSmall(String)
  case objectDisposed(String)
  case prepareLocalFailed(String)
  case outOfMemory(String)
  case cryptoFailure(String)
  case nullPointer(String)
  case invalidState(String)
  case replayAttackDetected(String)
  case sessionExpired(String)
  case postQuantumMissing(String)
  case groupProtocolError(String)
  case groupMembershipError(String)
  case treeIntegrityError(String)
  case welcomeError(String)
  case messageExpired(String)
  case frankingFailed(String)
  case genericError(String)

  static func from(errorCode: EPPNative.EppErrorCode, message: String = "") -> ProtocolError {
    let errorMessage: String =
      message.isEmpty ? EPPNative.errorCodeToString(errorCode) : message
    switch errorCode {
    case .success:
      return .genericError(
        errorMessage.isEmpty ? "Unexpected success code in error path" : errorMessage)
    case .errorGeneric:
      return .genericError(errorMessage)
    case .errorInvalidInput:
      return .invalidInput(errorMessage)
    case .errorKeyGeneration:
      return .keyGenerationFailed(errorMessage)
    case .errorDeriveKey:
      return .deriveKeyFailed(errorMessage)
    case .errorHandshake:
      return .handshakeFailed(errorMessage)
    case .errorEncryption:
      return .encryptionFailed(errorMessage)
    case .errorDecryption:
      return .decryptionFailed(errorMessage)
    case .errorDecode:
      return .decodeFailed(errorMessage)
    case .errorEncode:
      return .encodeFailed(errorMessage)
    case .errorBufferTooSmall:
      return .bufferTooSmall(errorMessage)
    case .errorObjectDisposed:
      return .objectDisposed(errorMessage)
    case .errorPrepareLocal:
      return .prepareLocalFailed(errorMessage)
    case .errorOutOfMemory:
      return .outOfMemory(errorMessage)
    case .errorCryptoFailure:
      return .cryptoFailure(errorMessage)
    case .errorNullPointer:
      return .nullPointer(errorMessage)
    case .errorInvalidState:
      return .invalidState(errorMessage)
    case .errorReplayAttack:
      return .replayAttackDetected(errorMessage)
    case .errorSessionExpired:
      return .sessionExpired(errorMessage)
    case .errorPqMissing:
      return .postQuantumMissing(errorMessage)
    case .errorGroupProtocol:
      return .groupProtocolError(errorMessage)
    case .errorGroupMembership:
      return .groupMembershipError(errorMessage)
    case .errorTreeIntegrity:
      return .treeIntegrityError(errorMessage)
    case .errorWelcome:
      return .welcomeError(errorMessage)
    case .errorMessageExpired:
      return .messageExpired(errorMessage)
    case .errorFranking:
      return .frankingFailed(errorMessage)
    }
  }

  var message: String {
    switch self {
    case .invalidInput(let msg),
      .keyGenerationFailed(let msg),
      .deriveKeyFailed(let msg),
      .handshakeFailed(let msg),
      .encryptionFailed(let msg),
      .decryptionFailed(let msg),
      .decodeFailed(let msg),
      .encodeFailed(let msg),
      .bufferTooSmall(let msg),
      .objectDisposed(let msg),
      .prepareLocalFailed(let msg),
      .outOfMemory(let msg),
      .cryptoFailure(let msg),
      .nullPointer(let msg),
      .invalidState(let msg),
      .replayAttackDetected(let msg),
      .sessionExpired(let msg),
      .postQuantumMissing(let msg),
      .groupProtocolError(let msg),
      .groupMembershipError(let msg),
      .treeIntegrityError(let msg),
      .welcomeError(let msg),
      .messageExpired(let msg),
      .frankingFailed(let msg),
      .genericError(let msg):
      return msg
    }
  }
}

extension ProtocolError {

  func toProtocolFailure() -> ProtocolFailure {
    switch self {
    case .invalidInput:
      return .invalidInput(message)
    case .keyGenerationFailed:
      return .keyGenerationFailed(message)
    case .deriveKeyFailed:
      return .keyDerivationFailed(message)
    case .handshakeFailed:
      return .handshakeFailed(message)
    case .encryptionFailed:
      return .encryptionFailed(message)
    case .decryptionFailed:
      return .decryptionFailed(message)
    case .decodeFailed, .encodeFailed:
      return .protocolStateMismatch(message)
    case .bufferTooSmall:
      return .bufferSizeMismatch(message)
    case .objectDisposed, .invalidState:
      return .protocolStateMismatch(message)
    case .prepareLocalFailed:
      return .handshakeFailed(message)
    case .outOfMemory:
      return .memoryAllocationFailed(message)
    case .cryptoFailure:
      return .cryptographicOperationFailed(message)
    case .nullPointer:
      return .invalidInput(message)
    case .replayAttackDetected:
      return .replayAttackDetected(message)
    case .sessionExpired:
      return .sessionExpired(message)
    case .postQuantumMissing:
      return .postQuantumKeyMissing(message)
    case .groupProtocolError:
      return .groupProtocolFailed(message)
    case .groupMembershipError:
      return .groupMembershipFailed(message)
    case .treeIntegrityError:
      return .treeIntegrityFailed(message)
    case .welcomeError:
      return .welcomeFailed(message)
    case .messageExpired:
      return .messageExpiredFailure(message)
    case .frankingFailed:
      return .frankingVerificationFailed(message)
    case .genericError:
      return .unexpectedError(message)
    }
  }
}

enum EPPConstants {

  static let X25519_PUBLIC_KEY_LENGTH: Int = 32
  static let ED25519_PUBLIC_KEY_LENGTH: Int = 32
  static let KYBER_PUBLIC_KEY_LENGTH: Int = 1184
  static let KYBER_CIPHERTEXT_LENGTH: Int = 1088
  static let KYBER_SHARED_SECRET_LENGTH: Int = 32
  static let SEED_LENGTH: Int = 32
  static let ROOT_KEY_LENGTH: Int = 32
  static let OPAQUE_SESSION_KEY_LENGTH: Int = 32
  static let HMAC_LENGTH: Int = 32
  static let AES_GCM_NONCE_LENGTH: Int = 12
  static let AES_GCM_TAG_LENGTH: Int = 16
}
