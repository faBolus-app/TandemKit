#!/usr/bin/env python3
"""
coverage_report.py — diff upstream jwoglom/pumpX2 messages against what TandemKit has ported.

Keeps the (large) parity program honest: prints, per category (request/response/historyLog), which
upstream message classes are NOT yet present as Swift types in TandemKit. "Present" = a
`struct <Name>` (for messages) or the class name appearing in a HistoryLogParser registration.

Usage:
    python3 scripts/coverage_report.py
    python3 scripts/coverage_report.py --missing     # only list gaps
    python3 scripts/coverage_report.py --category historyLog
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.dirname(HERE)
# Defaults to the vendored pumpX2 oracle submodule; override with PUMPX2_ORACLE_REF.
REF = os.environ.get(
    "PUMPX2_ORACLE_REF",
    os.path.join(KIT, "vendor/pumpx2-oracle/messages/src/main/java/com/jwoglom/pumpx2/pump/messages"))


def java_classes(subdir, exclude_subdirs=()):
    """All *.java class names under REF/<subdir> (recursively), minus test files.
    `exclude_subdirs` skips nested folders (e.g. exclude historyLog from the response walk)."""
    root = os.path.join(REF, subdir)
    names = set()
    for dirpath, dirnames, files in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in exclude_subdirs]
        for f in files:
            if f.endswith(".java") and not f.endswith("Test.java"):
                names.add(f[:-5])
    return names


def swift_symbols():
    """All `struct <Name>` declared anywhere in TandemKit Sources."""
    names = set()
    src = os.path.join(KIT, "Sources")
    pat = re.compile(r"\bstruct\s+([A-Za-z0-9_]+)")
    for dirpath, _, files in os.walk(src):
        for f in files:
            if f.endswith(".swift"):
                for line in open(os.path.join(dirpath, f)):
                    for m in pat.finditer(line):
                        names.add(m.group(1))
    return names


def report(category, ref_subdir, swift, missing_only):
    # The response walk must not double-count the historyLog subdir (reported separately).
    exclude = ("historyLog",) if category == "response" else ()
    ref = java_classes(ref_subdir, exclude_subdirs=exclude)
    have = {n for n in ref if n in swift}
    missing = sorted(ref - swift)
    total = len(ref)
    print(f"\n=== {category}: {len(have)}/{total} ported ({len(missing)} missing) ===")
    if not missing_only:
        for n in sorted(have):
            print(f"  ✓ {n}")
    for n in missing:
        print(f"  ✗ {n}")
    return len(have), total


def main():
    args = sys.argv[1:]
    missing_only = "--missing" in args
    only = None
    if "--category" in args:
        only = args[args.index("--category") + 1]

    swift = swift_symbols()
    cats = [
        ("request", "request"),
        ("response", "response"),
        ("historyLog", "response/historyLog"),
    ]
    done = tot = 0
    for name, sub in cats:
        if only and name != only:
            continue
        d, t = report(name, sub, swift, missing_only)
        done += d
        tot += t
    print(f"\n=== TOTAL: {done}/{tot} upstream message classes present as Swift structs ===")


if __name__ == "__main__":
    main()
