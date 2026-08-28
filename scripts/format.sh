#!/usr/bin/env bash
# format.sh — run swift-format over this package's Swift sources.
#
# `.swift-format` disables all 43 swift-format RULES and keeps only the pretty-printer, so this
# reflows whitespace and line breaks but never rewrites code — which matters here: the rules that
# rewrite code include ones that can widen access (NoAccessLevelOnExtensionDeclaration), delete a
# public memberwise init (UseSynthesizedInitializer), or insert underscores into numeric literals
# INCLUDING OPCODES (GroupNumericLiterals). The one rule left on is DoNotUseSemicolons, because the
# printer explodes `switch x { case a: …; case b: … }` one-liners onto separate lines and would
# otherwise leave a dangling `;` on each.
#
#   scripts/format.sh            # format in place
#   scripts/format.sh --lint     # report only, exit nonzero if anything is unformatted
set -euo pipefail
cd "$(dirname "$0")/.."

MODE=format
if [ "${1:-}" = "--lint" ]; then MODE=lint; fi

# git ls-files already excludes vendor/ (submodules) and .build.
FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(git ls-files '*.swift')

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no Swift files found — is this a TandemKit checkout?" >&2
  exit 1
fi

# Lint mode asks the only question that matters — "is the tree byte-identical to the formatter's
# output?" — rather than using `swift-format lint`. `lint --strict` also reports diagnostics the
# printer cannot act on (an end-of-line comment that pushes a line past the limit can only be fixed
# by MOVING the comment, which is a source change, not formatting), so it fails on a clean tree.
if [ "$MODE" = lint ]; then
  unformatted=()
  for f in "${FILES[@]}"; do
    if ! xcrun swift-format format "$f" | diff -q - "$f" >/dev/null 2>&1; then
      unformatted+=("$f")
    fi
  done
  if [ "${#unformatted[@]}" -gt 0 ]; then
    echo "❌ ${#unformatted[@]} file(s) are not formatted — run scripts/format.sh:" >&2
    printf '   %s\n' "${unformatted[@]}" >&2
    exit 1
  fi
  echo "✅ ${#FILES[@]} Swift files are formatted"
else
  printf '%s\n' "${FILES[@]}" | xargs xcrun swift-format format --in-place --parallel
  echo "✅ formatted ${#FILES[@]} Swift files"
fi
