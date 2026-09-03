# Software Bill of Materials (TandemKit)

Machine-checkable provenance for every third-party / vendored component TandemKit ships or builds
against. [`scripts/check-sbom.sh`](../scripts/check-sbom.sh) fails if a vendored submodule is missing a
row here, if a license string is outside the SPDX allowlist, or if a source file carries a third-party
provenance marker that no row backs. It runs as a non-blocking CI job (see `.github/workflows/ci.yml`).

Format per row: component · version/revision · SPDX license · source · how TandemKit uses it.

> **Disposition: NO-GO for real insulin delivery.** This inventory is documentation; it changes no
> delivery, dosing, or alerting behavior.

## First-party (this repo)

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| TandemKit (the Swift port) | in-repo | MIT | `Sources/` | Tandem t:slim X2 / Mobi protocol, auth (pairing + HMAC signing), and BLE transport. A hand-written Swift port of jwoglom/pumpx2 (MIT); each ported type's doc-comment cites its Java origin. Covered by the root `LICENSE`. |

## Vendored submodules

| Component | Version | License (SPDX) | Source | Usage |
|---|---|---|---|---|
| pumpx2-oracle | jwoglom/pumpx2 (© 2022 James Woglom) | MIT | `vendor/pumpx2-oracle` | The `cliparser` byte-parity oracle. **Tests only** — built to a JAR and compared against; never linked into a shipped product. |
| Mbed TLS | Mbed-TLS/mbedtls v3.6.7 | Apache-2.0 OR GPL-2.0-or-later | `vendor/mbedtls` | EC-JPAKE (secp256r1 / SHA-256) for the modern pairing handshake. Only the EC-JPAKE C sources are compiled — symlinked into `Sources/CMbedTLSJPAKE/mbedtls_lib/` (see `scripts/link-mbedtls.sh`) under a minimal config. Consumed via `TandemAuth`; the dual license is honored as **Apache-2.0** (see `NOTICE.md`). |

## Notes on provenance

- The entire `Sources/` tree is a hand-port of **jwoglom/pumpx2** (MIT); ported types are marked
  `// … Ported from <Class>.java`. `scripts/check-sbom.sh` scans `Sources/` for such markers and
  requires the pumpX2 upstream to be listed above.
- `.unsafeFlags` in `Package.swift` currently prevents consuming this package by URL+version — the
  §1.3 version-pin contract is declared **UNMET** (see `CONTRIBUTING.md` / `AGENTS.md`, WIP item 8).
  That is a packaging constraint, not a licensing one; it does not affect this inventory.

## Trademarks

"faBolus" is a trademark of Zev Granowitz (code is MIT; the name is not licensed). Tandem, t:slim X2, Mobi,
and Dexcom are trademarks of their respective owners; TandemKit is independent and unaffiliated. See
[`../NOTICE.md`](../NOTICE.md) for the full attribution prose.
