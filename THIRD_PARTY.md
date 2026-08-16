# Third-party components

TandemKit is MIT-licensed first-party software (see [`LICENSE`](LICENSE)). This file is a findable,
by-name index of the third-party and vendored components it builds on. It does **not** replace the
canonical sources — it points to them:

- [`LICENSE`](LICENSE) — the project's own MIT license.
- [`NOTICE.md`](NOTICE.md) — the authoritative attribution prose (pumpX2, Mbed TLS, trademarks).
- [`docs/SBOM.md`](docs/SBOM.md) — the machine-checked Software Bill of Materials, enforced by
  [`scripts/check-sbom.sh`](scripts/check-sbom.sh) in CI.

## Component summary

| Component | Upstream | License (SPDX) | Vendored at | Usage |
|---|---|---|---|---|
| pumpX2 protocol port | jwoglom/pumpx2 (© 2022 James Woglom) | MIT | hand-ported into `Sources/` | The Tandem message framing, opcodes, pairing (JPAKE + legacy V1), and HMAC signing are a Swift port of pumpX2. Covered by the root `LICENSE`; each ported type cites its Java origin. |
| pumpx2-oracle | jwoglom/pumpx2 (© 2022 James Woglom) | MIT | `vendor/pumpx2-oracle` (submodule) | The `cliparser` byte-parity oracle — **tests only**, never shipped. |
| Mbed TLS | Mbed-TLS/mbedtls (v3.6.7) | Apache-2.0 OR GPL-2.0-or-later | `vendor/mbedtls` (submodule) | EC-JPAKE (secp256r1 / SHA-256) for the modern pairing handshake, compiled into `CMbedTLSJPAKE`. Used as Apache-2.0 (see `NOTICE.md`). |

See [`docs/SBOM.md`](docs/SBOM.md) for the authoritative table and [`NOTICE.md`](NOTICE.md) for the
full prose.

## Trademarks

Not affiliated with, endorsed by, or a product of **Tandem Diabetes Care** or **Dexcom**. Tandem,
t:slim X2, Mobi, and Dexcom are trademarks of their respective owners. See [`NOTICE.md`](NOTICE.md).
