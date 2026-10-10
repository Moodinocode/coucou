#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/coucou-session-idle.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc NotchBuddy/Sources/App/SessionIdleTracker.swift \
    tests/SessionIdleTrackerTests.swift -o "$TEST_DIR/session-idle-tests"
"$TEST_DIR/session-idle-tests"
