/*
 * Thin C shim over mbedTLS EC-JPAKE (secp256r1 / SHA-256), exposing a flat API for Swift.
 * The client role only (we are always the central/app talking to the pump). RNG is supplied
 * internally via the OS CSPRNG (arc4random_buf) so no mbedTLS entropy/DRBG modules are needed.
 *
 * Return codes: 0 on success, negative mbedTLS error code otherwise.
 */
#ifndef CMBEDTLS_JPAKE_H
#define CMBEDTLS_JPAKE_H

#include <stddef.h>
#include <stdint.h>

typedef struct cjpake_ctx cjpake_ctx;

/* An mbedTLS f_rng: fill `out` with `len` random bytes, return 0. */
typedef int (*cjpake_rng_fn)(void *p_rng, unsigned char *out, size_t len);

/* Allocate + set up a CLIENT EC-JPAKE context with the given shared secret (the pairing
 * code bytes). Returns NULL on failure. */
cjpake_ctx *cjpake_new_client(const uint8_t *secret, size_t secret_len);

/* Server-role context. Used only for the in-process self-test handshake (the pump is the
 * real server in production). */
cjpake_ctx *cjpake_new_server(const uint8_t *secret, size_t secret_len);

/* Replace the OS CSPRNG with `f_rng`. Tests only: a seeded source makes a particular round (for
 * example one with a short ZKP scalar) reproducible. Production never calls this. */
void cjpake_set_rng(cjpake_ctx *ctx, cjpake_rng_fn f_rng, void *p_rng);

int cjpake_write_round_one(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len);
int cjpake_read_round_one(cjpake_ctx *ctx, const uint8_t *in, size_t in_len);
int cjpake_write_round_two(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len);
int cjpake_read_round_two(cjpake_ctx *ctx, const uint8_t *in, size_t in_len);
/* Derive the shared secret (TLS pre-master secret). */
int cjpake_derive_secret(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len);

void cjpake_free(cjpake_ctx *ctx);

#endif /* CMBEDTLS_JPAKE_H */
