#!/usr/bin/env bash
# Run the TandemKit test suite from the Command Line Tools (CLT), without full Xcode.
#
# CONVENIENCE, NOT A NECESSITY. Full Xcode IS installed on the dev machine and in CI
# (`.github/workflows/ci.yml` runs plain `swift test`), so this wrapper is not required — it is the
# CLT-only test path, kept for machines that have only the Command Line Tools. When only the CLT is
# present, plain `swift test` fails: the swift-testing framework ships with the CLT but isn't on
# SwiftPM's default search/rpath, and the SIP-protected swiftpm-testing-helper strips DYLD_* env
# vars. So we point the compiler/linker at the CLT-bundled Testing.framework and bake in the rpaths
# it needs at load time (the framework itself + lib_TestingInterop.dylib, which live in different
# dirs). With full Xcode selected via `xcode-select`, run plain `swift test` and skip this wrapper.
set -euo pipefail

FW="/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
LIB="/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

if [[ ! -d "$FW/Testing.framework" ]]; then
  echo "Testing.framework not found under CLT ($FW)." >&2
  echo "Install Xcode or newer Command Line Tools, then run 'swift test' directly." >&2
  exit 1
fi

exec swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$LIB" \
  "$@"
