#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-blank-spacing-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-blank-spacing.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/middle-blank.md"

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
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
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
  for step in $(seq 1 "$count"); do wtype -k Right; done
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
printf 'test\na\n\naa' > "$TEST_NOTE_PATH"
before_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1

wtype -M ctrl -k Home -m ctrl
top_state="$(wait_for_position 0)"
move_right 5
second_state="$(wait_for_position 5)"
move_right 2
blank_state="$(wait_for_position 7)"

jq -e --argjson top "$top_state" \
  --argjson second "$second_state" '
  .followingCursorY > .liveCursorY and
  (((.followingCursorY - .liveCursorY) -
    (.liveCursorY - $second.liveCursorY)) | fabs) < 0.5 and
  (((.liveCursorY - $second.liveCursorY) -
    ($second.liveCursorY - $top.liveCursorY)) | fabs) < 0.5
' <<<"$blank_state" >/dev/null || \
  fail "middle blank line used inconsistent spacing: top=$top_state second=$second_state blank=$blank_state"

grim "$ARTIFACT_DIR/jotpin-middle-blank-line-spacing.png"
move_right 1
wait_for_position 8 >/dev/null
after_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
[[ "$before_hash" == "$after_hash" ]] || \
  fail "caret navigation changed the spacing fixture bytes"
printf 'PASS: text, active blank, and following text use one line advance\n'
printf 'PASS: middle blank-line navigation preserves the Markdown source\n'
printf 'PASS: focused blank-line artifact captured in %s\n' "$ARTIFACT_DIR"
