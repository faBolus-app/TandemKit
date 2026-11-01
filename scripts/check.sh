#!/usr/bin/env bash
# The quality gates. CI runs each one as its own step; with no argument this runs them all.
#
#   scripts/check.sh                 # every gate
#   scripts/check.sh build format    # just these
#
# Gates: build, test, bench, format, swiftlint, shell, actions, markdown.
# `test` needs JDK 21 for the pumpx2 oracle: set PUMPX2_JAVA, or JAVA_HOME to a JDK 21.
set -euo pipefail
cd "$(dirname "$0")/.."

gate_build() { swift build --build-tests -Xswiftc -warnings-as-errors; }
# Same flags as gate_build, so running both doesn't compile everything twice.
gate_test() {
  if [ -z "${PUMPX2_JAVA:-}" ] && [ -n "${JAVA_HOME:-}" ]; then export PUMPX2_JAVA="$JAVA_HOME/bin/java"; fi
  swift test -Xswiftc -warnings-as-errors
}
# The bench package (Bench/) is built and tested on its own: the library never links it.
gate_bench() {
  swift build --package-path Bench --build-tests -Xswiftc -warnings-as-errors
  swift test --package-path Bench -Xswiftc -warnings-as-errors
}
gate_format() { git ls-files -z '*.swift' | xargs -0 xcrun swift-format lint --strict; }
gate_swiftlint() { swiftlint lint --strict --quiet; }
gate_shell() { git ls-files -z '*.sh' | xargs -0 shellcheck; }
gate_actions() { actionlint; }
gate_markdown() { markdownlint-cli2; }

gates=("$@")
[ "${#gates[@]}" -gt 0 ] || gates=(build test bench format swiftlint shell actions markdown)
for g in "${gates[@]}"; do
  echo "== $g"
  "gate_$g"
done
echo "all gates passed: ${gates[*]}"
