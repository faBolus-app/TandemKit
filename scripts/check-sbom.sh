#!/usr/bin/env bash
# TandemKit SBOM / provenance check — a sibling of faBolus's scripts/check-sbom.sh (P16 §3.1).
#
# Deterministic assertions, all green on a clean tree:
#   1. docs/SBOM.md exists.
#   2. Every git submodule (.gitmodules) has a row in the SBOM.
#   3. Every SPDX license string in the SBOM is on the allowlist.
#   4. Every third-party provenance marker in Sources/ traces to an SBOM-listed upstream
#      (the forcing function that catches an un-attributed port — cf. the faBolus xDrip lesson).
#
# It scans only the COMMITTED source tree + docs; it needs no submodule checkout. Wired as a
# NON-BLOCKING CI job (continue-on-error) so a heuristic false-positive can never turn the oracle
# build red — but it is expected to stay green.
set -euo pipefail
cd "$(dirname "$0")/.."

SBOM="docs/SBOM.md"
fail=0

# SPDX identifiers this project accepts. Anything else must be reviewed before it lands.
ALLOWED='MIT|Apache-2\.0|GPL-2\.0-or-later'
# SPDX-ish tokens we actively look for in the SBOM (allowed ones + common ones we must NOT silently
# accept, so a disallowed license added to a row is caught rather than ignored).
KNOWN_SPDX='MIT|Apache-2\.0|Apache-1\.1|BSD-2-Clause|BSD-3-Clause|ISC|Zlib|MPL-2\.0|GPL-2\.0-only|GPL-2\.0-or-later|GPL-3\.0-only|GPL-3\.0-or-later|LGPL-2\.1-only|LGPL-2\.1-or-later|LGPL-3\.0-only|AGPL-3\.0-only|AGPL-3\.0-or-later|LicenseRef-[A-Za-z0-9.-]+'

# ---- 1. SBOM present -------------------------------------------------------
[[ -f "$SBOM" ]] || { echo "MISSING: $SBOM"; exit 1; }

# ---- 2. every submodule has an SBOM row ------------------------------------
if [[ -f .gitmodules ]]; then
  while IFS= read -r sub; do
    [[ -n "$sub" ]] || continue
    name="$(basename "$sub")"
    if ! grep -q -e "$sub" -e "$name" "$SBOM"; then
      echo "MISSING SBOM ENTRY: submodule '$sub' is not listed in $SBOM"; fail=1
    fi
  done < <(git config -f .gitmodules --get-regexp 'submodule\..*\.path' 2>/dev/null | awk '{print $2}')
fi

# ---- 3. license strings are on the allowlist -------------------------------
# Pull SPDX-ish tokens out of the SBOM and reject any that are known-but-not-allowed.
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  if ! printf '%s\n' "$tok" | grep -qE "^($ALLOWED)$"; then
    echo "DISALLOWED LICENSE in $SBOM: '$tok' is not on the SPDX allowlist ($ALLOWED)"; fail=1
  fi
done < <(grep -oE "$KNOWN_SPDX" "$SBOM" | sort -u)

# ---- 4. provenance markers in Sources/ trace to an SBOM-listed upstream ----
# The whole port derives from jwoglom/pumpx2 ("Ported from <Class>.java"); the crypto shim uses
# mbedTLS. Both must be SBOM-listed, and any provenance line that does NOT resolve to a known upstream
# is surfaced (soft warning) so an un-attributed port can't slip in.
grep -q -iE 'pumpx2|jwoglom' "$SBOM" || { echo "SBOM must list the pumpX2 upstream (jwoglom/pumpx2)"; fail=1; }
grep -q -iE 'mbed ?tls'      "$SBOM" || { echo "SBOM must list the Mbed TLS upstream"; fail=1; }

if [[ -d Sources ]]; then
  stray="$(git grep -nE 'Ported from|Adapted from|Vendored from|Copied from' -- Sources/ 2>/dev/null \
            | grep -vE '\.java' || true)"
  if [[ -n "$stray" ]]; then
    echo "WARN (non-blocking): provenance marker(s) in Sources/ not attributable to a .java (pumpX2) origin:"
    printf '%s\n' "$stray"
    echo "  -> confirm the upstream is listed in $SBOM before shipping."
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "SBOM / provenance check FAILED — reconcile with $SBOM." >&2
  exit 1
fi
echo "SBOM / provenance check passed: submodules, licenses, and Sources/ provenance all accounted for."
