#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-code-escape-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-code-escape.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/code-escape.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}' | tail -n 1
}

wait_for_auto_fence() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 3 and .sourceLength == 9 and
      .sourceLine == 0 and .targetBlockType == "code" and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "auto-completed fence did not settle with a trailing escape line: $state"
}

wait_for_code_body() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 4 and .sourceLength == 9 and
      .sourceLine == 1 and .targetBlockType == "code" and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "Down did not reach the generated empty code row: $state"
}

wait_for_escape_line() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 9 and .sourceLength == 9 and
      .sourceLine == 3 and .targetBlockType == "blank" and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "Down did not escape below the generated code block: $state"
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell grim wtype jq; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
: > "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1

wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
sleep 0.1
wtype -d 30 -- '```'
wait_for_auto_fence >/dev/null

wtype -k Down
wait_for_code_body >/dev/null
wtype -k Down
wtype -k Down
escape_state="$(wait_for_escape_line)"
grim "$ARTIFACT_DIR/jotpin-code-block-escape-line.png"

printf 'PASS: generated fences include a trailing editable line\n'
printf 'PASS: Down reaches the generated empty code row\n'
printf 'PASS: continued Down escapes to the editable line after the code block\n'
printf 'PASS: focused code-block escape artifact captured in %s\n' "$ARTIFACT_DIR"
