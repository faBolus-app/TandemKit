#!/usr/bin/env bash
# The quality gates. CI runs each one as its own step; with no argument this runs them all.
#
#   scripts/check.sh                 # every gate
#   scripts/check.sh build format    # just these
#
# Gates: build, test, format, swiftlint, shell, actions, markdown.
# `test` needs JDK 21 for the pumpx2 oracle: set PUMPX2_JAVA, or JAVA_HOME to a JDK 21.
set -euo pipefail
cd "$(dirname "$0")/.."

gate_build() { swift build --build-tests -Xswiftc -warnings-as-errors; }
gate_test() { PUMPX2_JAVA="${PUMPX2_JAVA:-${JAVA_HOME:+$JAVA_HOME/bin/java}}" swift test; }
gate_format() { git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict; }
gate_swiftlint() { swiftlint lint --strict --quiet; }
gate_shell() { git ls-files -z '*.sh' | xargs -0 shellcheck; }
gate_actions() { actionlint; }
gate_markdown() { markdownlint-cli2; }

gates=("$@")
[ "${#gates[@]}" -gt 0 ] || gates=(build test format swiftlint shell actions markdown)
for g in "${gates[@]}"; do
  echo "== $g"
  "gate_$g"
done
echo "all gates passed: ${gates[*]}"
