# Attributions

TandemKit is an independent, open-source Swift package, licensed under the MIT License (see
`LICENSE`). It is an independent reimplementation — not a fork of, affiliated with, or endorsed by
the projects below.

## pumpX2 (protocol origin)
The Tandem pump message framing, opcodes, pairing (JPAKE), and HMAC signing are ports of the
protocol reverse-engineered by **[pumpX2](https://github.com/jwoglom/pumpx2)** (© 2022 James Woglom,
MIT License). Outgoing messages are validated byte-for-byte against pumpX2's `cliparser` oracle,
which is included as a git submodule under `vendor/pumpx2-oracle` (retains its own MIT LICENSE).

## Mbed TLS (vendored crypto)
The EC-JPAKE implementation uses **[Mbed TLS](https://github.com/Mbed-TLS/mbedtls)**, included as a
git submodule under `vendor/mbedtls` and dual-licensed **Apache-2.0 OR GPL-2.0-or-later**
(© The Mbed TLS Contributors). Only the EC-JPAKE C sources are compiled, via symlinks into the
submodule; their SPDX headers are retained.

## Trademarks
TandemKit is part of the **faBolus™** project; faBolus™ is a trademark of Tia Geri.

Not affiliated with, endorsed by, or a product of **Tandem Diabetes Care** or **Dexcom**. Tandem,
t:slim X2, Mobi, and Dexcom are trademarks of their respective owners.
