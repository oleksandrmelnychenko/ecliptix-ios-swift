#if defined(EPP_ENABLE_STUBS)

#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint8_t *data;
    intptr_t length;
} epp_buffer_t;

typedef struct {
    uint32_t max_messages_per_chain;
} epp_session_config_t;

enum {
    EPP_SUCCESS = 0,
    EPP_ERROR_GENERIC = 1,
    EPP_ERROR_INVALID_INPUT = 2,
    EPP_ERROR_KEY_GENERATION = 3,
    EPP_ERROR_DERIVE_KEY = 4,
    EPP_ERROR_HANDSHAKE = 5,
    EPP_ERROR_ENCRYPTION = 6,
    EPP_ERROR_DECRYPTION = 7,
    EPP_ERROR_DECODE = 8,
    EPP_ERROR_ENCODE = 9,
    EPP_ERROR_BUFFER_TOO_SMALL = 10,
    EPP_ERROR_OBJECT_DISPOSED = 11,
    EPP_ERROR_PREPARE_LOCAL = 12,
    EPP_ERROR_OUT_OF_MEMORY = 13,
    EPP_ERROR_CRYPTO_FAILURE = 14,
    EPP_ERROR_NULL_POINTER = 15,
    EPP_ERROR_INVALID_STATE = 16,
    EPP_ERROR_REPLAY_ATTACK = 17,
    EPP_ERROR_SESSION_EXPIRED = 18,
    EPP_ERROR_PQ_MISSING = 19
};

static void set_error(int32_t *out_error, int32_t code) {
    if (out_error != NULL) {
        *out_error = code;
    }
}

static int32_t alloc_handle(void **out_handle, int32_t *out_error) {
    if (out_handle == NULL) {
        set_error(out_error, EPP_ERROR_NULL_POINTER);
        return EPP_ERROR_NULL_POINTER;
    }

    void *handle = malloc(1);
    if (handle == NULL) {
        set_error(out_error, EPP_ERROR_OUT_OF_MEMORY);
        return EPP_ERROR_OUT_OF_MEMORY;
    }

    *out_handle = handle;
    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

static int32_t alloc_buffer(epp_buffer_t *out_buffer, intptr_t length, int32_t *out_error) {
    if (out_buffer == NULL) {
        set_error(out_error, EPP_ERROR_NULL_POINTER);
        return EPP_ERROR_NULL_POINTER;
    }

    if (length < 0) {
        length = 0;
    }

    uint8_t *data = NULL;
    if (length > 0) {
        data = (uint8_t *)calloc((size_t)length, sizeof(uint8_t));
        if (data == NULL) {
            out_buffer->data = NULL;
            out_buffer->length = 0;
            set_error(out_error, EPP_ERROR_OUT_OF_MEMORY);
            return EPP_ERROR_OUT_OF_MEMORY;
        }
    }

    out_buffer->data = data;
    out_buffer->length = length;
    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

const char *epp_version(void) {
    return "epp-stub-1.0";
}

int32_t epp_init(void) {
    return EPP_SUCCESS;
}

void epp_shutdown(void) {
}

int32_t epp_identity_create(void **out_handle, int32_t *out_error) {
    return alloc_handle(out_handle, out_error);
}

int32_t epp_identity_create_from_seed(
    const uint8_t *seed,
    intptr_t seed_length,
    void **out_handle,
    int32_t *out_error
) {
    (void)seed;
    (void)seed_length;
    return alloc_handle(out_handle, out_error);
}

int32_t epp_identity_create_with_context(
    const uint8_t *seed,
    intptr_t seed_length,
    const char *membership_id,
    intptr_t membership_id_length,
    void **out_handle,
    int32_t *out_error
) {
    (void)seed;
    (void)seed_length;
    (void)membership_id;
    (void)membership_id_length;
    return alloc_handle(out_handle, out_error);
}

int32_t epp_identity_get_x25519_public(
    void *handle,
    uint8_t *out_key,
    intptr_t out_key_length,
    int32_t *out_error
) {
    if (handle == NULL || out_key == NULL || out_key_length <= 0) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }
    memset(out_key, 0, (size_t)out_key_length);
    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

int32_t epp_identity_get_ed25519_public(
    void *handle,
    uint8_t *out_key,
    intptr_t out_key_length,
    int32_t *out_error
) {
    return epp_identity_get_x25519_public(handle, out_key, out_key_length, out_error);
}

int32_t epp_identity_get_kyber_public(
    void *handle,
    uint8_t *out_key,
    intptr_t out_key_length,
    int32_t *out_error
) {
    return epp_identity_get_x25519_public(handle, out_key, out_key_length, out_error);
}

void epp_identity_destroy(void *handle) {
    if (handle != NULL) {
        free(handle);
    }
}

int32_t epp_prekey_bundle_create(
    void *identity_handle,
    epp_buffer_t *out_bundle,
    int32_t *out_error
) {
    (void)identity_handle;
    return alloc_buffer(out_bundle, 256, out_error);
}

int32_t epp_handshake_initiator_start(
    void *identity_handle,
    const uint8_t *peer_prekey_bundle,
    intptr_t peer_prekey_bundle_length,
    const epp_session_config_t *config,
    void **out_handle,
    epp_buffer_t *out_handshake_init,
    int32_t *out_error
) {
    (void)identity_handle;
    (void)peer_prekey_bundle;
    (void)peer_prekey_bundle_length;
    (void)config;

    int32_t code = alloc_handle(out_handle, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    return alloc_buffer(out_handshake_init, 128, out_error);
}

int32_t epp_handshake_initiator_finish(
    void *handle,
    const uint8_t *handshake_ack,
    intptr_t handshake_ack_length,
    void **out_session,
    int32_t *out_error
) {
    (void)handle;
    (void)handshake_ack;
    (void)handshake_ack_length;
    return alloc_handle(out_session, out_error);
}

void epp_handshake_initiator_destroy(void *handle) {
    if (handle != NULL) {
        free(handle);
    }
}

int32_t epp_session_encrypt(
    void *handle,
    const uint8_t *plaintext,
    intptr_t plaintext_length,
    int32_t envelope_type,
    uint32_t envelope_id,
    const uint8_t *correlation_id,
    intptr_t correlation_id_length,
    epp_buffer_t *out_encrypted_envelope,
    int32_t *out_error
) {
    (void)envelope_type;
    (void)envelope_id;
    (void)correlation_id;
    (void)correlation_id_length;

    if (handle == NULL || out_encrypted_envelope == NULL) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }

    intptr_t length = plaintext_length > 0 ? plaintext_length : 1;
    int32_t code = alloc_buffer(out_encrypted_envelope, length, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    if (plaintext != NULL && plaintext_length > 0 && out_encrypted_envelope->data != NULL) {
        memcpy(out_encrypted_envelope->data, plaintext, (size_t)plaintext_length);
    }

    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

int32_t epp_session_decrypt(
    void *handle,
    const uint8_t *encrypted_envelope,
    intptr_t encrypted_envelope_length,
    epp_buffer_t *out_plaintext,
    epp_buffer_t *out_metadata,
    int32_t *out_error
) {
    if (handle == NULL || out_plaintext == NULL || out_metadata == NULL) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }

    intptr_t payload_length = encrypted_envelope_length > 0 ? encrypted_envelope_length : 1;
    int32_t code = alloc_buffer(out_plaintext, payload_length, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    if (encrypted_envelope != NULL && encrypted_envelope_length > 0 && out_plaintext->data != NULL) {
        memcpy(out_plaintext->data, encrypted_envelope, (size_t)encrypted_envelope_length);
    }

    code = alloc_buffer(out_metadata, 16, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

int32_t epp_session_serialize(
    void *handle,
    const uint8_t *encryption_key,
    intptr_t encryption_key_length,
    epp_buffer_t *out_sealed_state,
    int32_t *out_error
) {
    (void)handle;
    (void)encryption_key;
    (void)encryption_key_length;
    return alloc_buffer(out_sealed_state, 128, out_error);
}

int32_t epp_session_deserialize(
    const uint8_t *sealed_state_bytes,
    intptr_t sealed_state_bytes_length,
    const uint8_t *decryption_key,
    intptr_t decryption_key_length,
    void **out_handle,
    int32_t *out_error
) {
    (void)sealed_state_bytes;
    (void)sealed_state_bytes_length;
    (void)decryption_key;
    (void)decryption_key_length;
    return alloc_handle(out_handle, out_error);
}

void epp_session_destroy(void *handle) {
    if (handle != NULL) {
        free(handle);
    }
}

int32_t epp_envelope_validate(
    const uint8_t *encrypted_envelope,
    intptr_t encrypted_envelope_length,
    int32_t *out_error
) {
    if (encrypted_envelope == NULL || encrypted_envelope_length <= 0) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }

    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

int32_t epp_shamir_split(
    const uint8_t *secret,
    intptr_t secret_length,
    uint8_t threshold,
    uint8_t share_count,
    const uint8_t *auth_key,
    intptr_t auth_key_length,
    epp_buffer_t *out_shares,
    intptr_t *out_share_length,
    int32_t *out_error
) {
    (void)threshold;
    (void)auth_key;
    (void)auth_key_length;

    if (secret == NULL || secret_length <= 0 || share_count == 0 || out_shares == NULL || out_share_length == NULL) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }

    *out_share_length = secret_length;
    intptr_t total_length = secret_length * (intptr_t)share_count;

    int32_t code = alloc_buffer(out_shares, total_length, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    for (uint8_t index = 0; index < share_count; index++) {
        memcpy(out_shares->data + ((intptr_t)index * secret_length), secret, (size_t)secret_length);
    }

    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

int32_t epp_shamir_reconstruct(
    const uint8_t *shares,
    intptr_t shares_length,
    intptr_t share_length,
    intptr_t share_count,
    const uint8_t *auth_key,
    intptr_t auth_key_length,
    epp_buffer_t *out_secret,
    int32_t *out_error
) {
    (void)share_count;
    (void)auth_key;
    (void)auth_key_length;

    if (shares == NULL || shares_length <= 0 || share_length <= 0 || out_secret == NULL) {
        set_error(out_error, EPP_ERROR_INVALID_INPUT);
        return EPP_ERROR_INVALID_INPUT;
    }

    int32_t code = alloc_buffer(out_secret, share_length, out_error);
    if (code != EPP_SUCCESS) {
        return code;
    }

    memcpy(out_secret->data, shares, (size_t)share_length);
    set_error(out_error, EPP_SUCCESS);
    return EPP_SUCCESS;
}

void epp_buffer_release(epp_buffer_t *buffer) {
    if (buffer == NULL) {
        return;
    }

    if (buffer->data != NULL) {
        free(buffer->data);
    }

    buffer->data = NULL;
    buffer->length = 0;
}

void *epp_buffer_alloc(intptr_t capacity) {
    if (capacity <= 0) {
        return NULL;
    }
    return malloc((size_t)capacity);
}

void epp_buffer_free(void *buffer) {
    if (buffer != NULL) {
        free(buffer);
    }
}

int32_t epp_secure_wipe(void *data, intptr_t length) {
    if (data == NULL || length <= 0) {
        return EPP_ERROR_INVALID_INPUT;
    }

    memset(data, 0, (size_t)length);
    return EPP_SUCCESS;
}

#endif
