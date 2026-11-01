#include "cmbedtls_jpake.h"

#include <stdlib.h>
#include "mbedtls/ecjpake.h"

struct cjpake_ctx {
    mbedtls_ecjpake_context ec;
    cjpake_rng_fn f_rng;
    void *p_rng;
};

/* OS CSPRNG as an mbedtls f_rng. arc4random_buf never fails. */
static int cjpake_rng(void *p_rng, unsigned char *out, size_t len) {
    (void)p_rng;
    arc4random_buf(out, len);
    return 0;
}

static cjpake_ctx *cjpake_new_role(mbedtls_ecjpake_role role,
                                   const uint8_t *secret, size_t secret_len) {
    cjpake_ctx *c = calloc(1, sizeof(cjpake_ctx));
    if (!c) return NULL;
    c->f_rng = cjpake_rng;
    c->p_rng = NULL;
    mbedtls_ecjpake_init(&c->ec);
    int rc = mbedtls_ecjpake_setup(&c->ec, role, MBEDTLS_MD_SHA256,
                                   MBEDTLS_ECP_DP_SECP256R1, secret, secret_len);
    if (rc != 0) {
        mbedtls_ecjpake_free(&c->ec);
        free(c);
        return NULL;
    }
    return c;
}

cjpake_ctx *cjpake_new_client(const uint8_t *secret, size_t secret_len) {
    return cjpake_new_role(MBEDTLS_ECJPAKE_CLIENT, secret, secret_len);
}

cjpake_ctx *cjpake_new_server(const uint8_t *secret, size_t secret_len) {
    return cjpake_new_role(MBEDTLS_ECJPAKE_SERVER, secret, secret_len);
}

void cjpake_set_rng(cjpake_ctx *ctx, cjpake_rng_fn f_rng, void *p_rng) {
    ctx->f_rng = f_rng;
    ctx->p_rng = p_rng;
}

int cjpake_write_round_one(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len) {
    return mbedtls_ecjpake_write_round_one(&ctx->ec, out, out_cap, out_len, ctx->f_rng, ctx->p_rng);
}

int cjpake_read_round_one(cjpake_ctx *ctx, const uint8_t *in, size_t in_len) {
    return mbedtls_ecjpake_read_round_one(&ctx->ec, in, in_len);
}

int cjpake_write_round_two(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len) {
    return mbedtls_ecjpake_write_round_two(&ctx->ec, out, out_cap, out_len, ctx->f_rng, ctx->p_rng);
}

int cjpake_read_round_two(cjpake_ctx *ctx, const uint8_t *in, size_t in_len) {
    return mbedtls_ecjpake_read_round_two(&ctx->ec, in, in_len);
}

int cjpake_derive_secret(cjpake_ctx *ctx, uint8_t *out, size_t out_cap, size_t *out_len) {
    return mbedtls_ecjpake_derive_secret(&ctx->ec, out, out_cap, out_len, ctx->f_rng, ctx->p_rng);
}

void cjpake_free(cjpake_ctx *ctx) {
    if (!ctx) return;
    mbedtls_ecjpake_free(&ctx->ec);
    free(ctx);
}
