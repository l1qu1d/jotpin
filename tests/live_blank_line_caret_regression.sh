#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-blank-caret-artifacts}"
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-blank-caret.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/middle-blank-line.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

wait_for_position() {
  local expected_position="$1"
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e --argjson position "$expected_position" '
      .cursorPosition == $position and
      .liveCursorVisible and .liveCursorSourcePosition == $position and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "caret did not settle at source position $expected_position: $state"
}

move_right() {
  local count="$1"
  local step
  for step in $(seq 1 "$count"); do
    wtype -k Right
  done
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
cp -- "$ROOT_DIR/tests/fixtures/middle-blank-line.md" "$TEST_NOTE_PATH"
before_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1

wtype -M ctrl -k Home -m ctrl
move_right 4
text_state="$(wait_for_position 4)"
move_right 1
blank_state="$(wait_for_position 5)"

if ! jq -e --argjson blank "$blank_state" '
  (((.followingCursorY - $blank.followingCursorY) | fabs) < 0.5) and
  ((($blank.liveCursorY - .liveCursorY) -
    ($blank.followingCursorY - $blank.liveCursorY)) | fabs) < 0.5
' <<<"$text_state" >/dev/null; then
  fail "entering the blank row changed the following text geometry: text=$text_state blank=$blank_state"
fi

move_right 3
wait_for_position 8 >/dev/null
wtype -k Up
up_blank_state="$(wait_for_position 5)"
jq -e '.sourceLine == 1 and .targetBlockType == "blank"' \
  <<<"$up_blank_state" >/dev/null || \
  fail "Up from aa skipped the blank source line: $up_blank_state"

grim "$ARTIFACT_DIR/jotpin-middle-blank-line-caret.png"
after_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
[[ "$before_hash" == "$after_hash" ]] || \
  fail "caret navigation changed the blank-line fixture bytes"
printf 'PASS: the blank row remains targetable before the caret enters it\n'
printf 'PASS: entering the blank row does not move the following text\n'
printf 'PASS: Up from the following text lands on the blank row\n'
printf 'PASS: blank-line caret fixture remains source-preserving\n'
