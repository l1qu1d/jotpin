#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-qml-health.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/vertical-navigation.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

for command in omarchy-shell journalctl; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

cp -- "$ROOT_DIR/tests/fixtures/vertical-navigation.md" "$TEST_NOTE_PATH"

readonly START_TIME="$(date --iso-8601=seconds)"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"side\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 0.5
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 0.5
omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true

plugin_errors="$(
  journalctl --user -t omarchy-shell --since "$START_TIME" --no-pager |
    rg 'dev\.jotpin|JotPin\.qml|MarkdownDisplay\.qml' |
    rg 'Binding loop|TypeError|ReferenceError|Cannot assign|is not defined|failed to load' || true
)"

[[ -z "$plugin_errors" ]] || fail "JotPin emitted QML runtime errors:\n$plugin_errors"
printf 'PASS: side and center modes emitted no JotPin QML runtime errors\n'
