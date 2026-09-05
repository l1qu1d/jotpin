#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-gap-navigation-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-gap-navigation.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/scratchpad.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

wait_for_blank_line() {
  local attempt state
  for attempt in $(seq 1 60); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 5 and .sourceLine == 1 and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      .targetBlockType == "blank" and .targetItemIndex == -1
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.02
  done
  fail "Down did not enter the Markdown blank line: $state"
}

wait_for_first_list_item() {
  local attempt state
  for attempt in $(seq 1 60); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 6 and .sourceLine == 2 and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      .targetBlockType == "list" and .targetItemIndex == 0
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.02
  done
  fail "Down did not continue from the blank line to the list: $state"
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell grim wtype jq sha256sum; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
cp -- "$ROOT_DIR/tests/fixtures/markdown-gap-navigation.md" "$TEST_NOTE_PATH"
before_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1

wtype -M ctrl -k Home -m ctrl
wtype -k End
sleep 0.05
before_state="$(caret_state)"
jq -e '.cursorPosition == 4 and .sourceLine == 0' \
  <<<"$before_state" >/dev/null || \
  fail "fixture did not start at the end of test: $before_state"

wtype -k Down
blank_state="$(wait_for_blank_line)"
after_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
[[ "$before_hash" == "$after_hash" ]] || \
  fail "Down changed the note bytes: $before_hash -> $after_hash"

wtype -k Down
after_state="$(wait_for_first_list_item)"
grim "$ARTIFACT_DIR/jotpin-down-through-markdown-blank-line.png"

printf 'PASS: Down enters the source-only Markdown blank line\n'
printf 'PASS: Down continues from the blank line to the first list item\n'
printf 'PASS: Down preserves the note bytes and lands visibly on hi\n'
printf 'PASS: focused navigation artifact captured in %s\n' "$ARTIFACT_DIR"
