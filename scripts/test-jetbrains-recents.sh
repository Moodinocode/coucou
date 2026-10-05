#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-jetbrains-recents.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/JetBrainsRecentProjects.swift \
    tests/JetBrainsRecentProjectsTests.swift -o "$TEST_DIR/jetbrains-recents-tests"
"$TEST_DIR/jetbrains-recents-tests"
