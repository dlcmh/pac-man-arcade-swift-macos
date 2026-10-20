#!/bin/sh
# PAC-MAN — Metal Arcade.
#
# The verification gate. Run this before every commit, or `make check`.
#
# Stages:
#   1. swift-format lint   — style, line length, one statement per line
#   2. release build with -warnings-as-errors
#                          — unused variables, dead stores, unreachable code;
#                            the closest thing Swift has to a linter
#   3. PacManChecks        — the simulation regression suite
#   4. docs-check          — documentation links and cited symbols
#
# There is no Clippy equivalent that ships with the Swift toolchain, and this
# repository takes no third-party dependencies, so the gate uses only what the
# Apple Command Line Tools already provide: `swift-format` and the compiler.
#
# `swift-format lint` is what CI-less contributors should run after edits;
# `xcrun swift-format format --in-place --recursive Sources Checks` applies the
# house style in `.swift-format`. `Sources/PacManArcade/MetalShaders.swift`
# opts out with `// swift-format-ignore-file` because its payload is an MSL
# string literal that the formatter would re-indent.

set -eu
cd "$(dirname "$0")/.."

SWIFT="${SWIFT:-swift}"
SWIFT_FORMAT="${SWIFT_FORMAT:-xcrun swift-format}"
SWIFT_ARGS="${SWIFT_ARGS:-}"

echo "==> swift-format lint"
$SWIFT_FORMAT lint --recursive Sources Checks

echo "==> build (release, warnings as errors)"
# shellcheck disable=SC2086
$SWIFT build -c release -Xswiftc -warnings-as-errors $SWIFT_ARGS

echo "==> simulation checks"
# shellcheck disable=SC2086
$SWIFT run $SWIFT_ARGS PacManChecks

echo "==> docs-check"
python3 scripts/check_docs.py

echo "==> all checks passed"
