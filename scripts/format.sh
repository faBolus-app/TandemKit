#!/usr/bin/env bash
# Format every Swift file in place with the toolchain's swift-format (Xcode 27.2). `.swift-format`
# keeps only the pretty-printer and DoNotUseSemicolons, so this reflows layout but never rewrites
# code (no rule that could widen access, drop an init, or regroup the digits of an opcode).
# `scripts/check.sh format` is the matching lint.
set -euo pipefail
cd "$(dirname "$0")/.."
git ls-files -z '*.swift' | xargs -0 xcrun swift-format format --in-place --parallel
