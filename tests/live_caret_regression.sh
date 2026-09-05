#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-caret-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-caret.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/caret-regression.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

close_plugin() {
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  close_plugin
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell grim wtype jq; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
cp -- "$ROOT_DIR/tests/fixtures/paragraph-caret-soft-breaks.md" "$TEST_NOTE_PATH"

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

assert_state_is_not_stale() {
  local state="$1"
  jq -e '
    (.liveCursorVisible | not) or
    (.liveCursorSourcePosition == .cursorPosition and
     .layoutReady and .layoutSourceMatches and .layoutCursorMatches)
  ' <<<"$state" >/dev/null || fail "a visible caret used stale editor state: $state"
}

wait_for_current_caret() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    assert_state_is_not_stale "$state"
    if jq -e '
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail 'the caret did not settle on the current source position'
}

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1
wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
sleep 0.1
wtype -d 25 -- 'test a'
wtype -k Return
sleep 0.08
wtype a
wtype -k Return
sleep 0.08
wtype a
wtype -k Return
sleep 0.08
wtype az

state="$(wait_for_current_caret)"
jq -e '.sourceLength == 13' <<<"$state" >/dev/null || \
  fail "the focused typing fixture was not entered completely: $state"
jq -e '
  (.liveCursorHeight >= (.nativeCursorHeight - 1)) and
  (.liveCursorHeight <= (.nativeCursorHeight + 1))
' <<<"$state" >/dev/null || fail "caret height does not match the native font metrics: $state"
grim "$ARTIFACT_DIR/jotpin-caret-font-height.png"

# A rendered heading uses a larger font than the source editor. Its caret must
# scale by the same factor instead of retaining the body-font height.
wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
sleep 0.1
wtype -d 25 -- '# Heading'
heading_state="$(wait_for_current_caret)"
jq -e '
  (.liveCursorHeight >= ((.nativeCursorHeight * 1.55) - 1)) and
  (.liveCursorHeight <= ((.nativeCursorHeight * 1.55) + 1))
' <<<"$heading_state" >/dev/null || \
  fail "heading caret did not scale with the rendered font: $heading_state"
grim "$ARTIFACT_DIR/jotpin-caret-heading-font-height.png"

# Restore the multiline paragraph before exercising deletion behavior.
wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
sleep 0.1
wtype -d 25 -- 'test a'
wtype -k Return
sleep 0.08
wtype a
wtype -k Return
sleep 0.08
wtype a
wtype -k Return
sleep 0.08
wtype az
wait_for_current_caret >/dev/null

# Exercise deletion within a line, across a newline, and after the block shape
# changes. A visible caret is never allowed to represent an older revision.
for deletion in 1 2 3; do
  wtype -k BackSpace
  assert_state_is_not_stale "$(caret_state)"
  wait_for_current_caret >/dev/null
done
grim "$ARTIFACT_DIR/jotpin-caret-backspace-lines.png"

# Hold Backspace long enough to trigger key repeat and sample the live state
# while source and cursor revisions are changing rapidly.
before_hold="$(caret_state)"
wtype -P BackSpace -s 650 -p BackSpace &
wtype_pid=$!
while kill -0 "$wtype_pid" >/dev/null 2>&1; do
  assert_state_is_not_stale "$(caret_state)"
  sleep 0.015
done
wait "$wtype_pid"
after_hold="$(wait_for_current_caret)"
jq -e --argjson before "$before_hold" \
  '.sourceLength < $before.sourceLength' <<<"$after_hold" >/dev/null || \
  fail 'held Backspace did not delete text'
grim "$ARTIFACT_DIR/jotpin-caret-held-backspace.png"

printf 'PASS: caret height follows native font metrics\n'
printf 'PASS: caret height scales with rendered heading fonts\n'
printf 'PASS: single and held Backspace never exposed a stale visible caret\n'
printf 'PASS: focused caret artifacts captured in %s\n' "$ARTIFACT_DIR"
