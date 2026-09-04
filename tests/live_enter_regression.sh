#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-enter-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-enter.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/enter.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

wait_for_current_caret() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 5 and .sourceLength == 5 and .sourceLine == 1 and
      .targetBlockType == "blank" and
      .liveCursorVisible and .liveCursorSourcePosition == 5 and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "Enter caret did not settle on the new line: $state"
}

wait_for_typed_caret() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 6 and .sourceLength == 6 and .sourceLine == 1 and
      .targetBlockType == "paragraph" and
      .liveCursorVisible and .liveCursorSourcePosition == 6 and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "typed second-line caret did not settle: $state"
}

wait_for_three_line_bottom() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 8 and .sourceLength == 8 and .sourceLine == 2 and
      .targetBlockType == "paragraph" and
      .liveCursorVisible and .liveCursorSourcePosition == 8 and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "three-line bottom caret did not settle: $state"
}

wait_for_three_line_top() {
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e '
      .cursorPosition == 0 and .sourceLength == 8 and .sourceLine == 0 and
      .targetBlockType == "paragraph" and
      .liveCursorVisible and .liveCursorSourcePosition == 0 and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "three-line top caret did not settle: $state"
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
printf '' > "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1
wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
sleep 0.1
initial_state="$(caret_state)"
jq -e '.cursorPosition == 0 and .sourceLength == 0' \
  <<<"$initial_state" >/dev/null || \
  fail "disposable Enter fixture did not start empty: $initial_state"

wtype -d 30 -- test
sleep 0.1
before_state="$(caret_state)"
jq -e '
  .cursorPosition == 4 and .sourceLine == 0 and .liveCursorVisible and
  .liveCursorSourcePosition == 4 and
  ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
' <<<"$before_state" >/dev/null || \
  fail "caret was not settled at the end of test: $before_state"

wtype -k Return
immediate_state="$(caret_state)"
jq -e '
  .cursorPosition == 5 and .sourceLine == 1 and
  ((.liveCursorVisible | not) or
   ((.liveCursorY - .renderedCursorY) | fabs) < 0.5)
' <<<"$immediate_state" >/dev/null || \
  fail "Enter briefly exposed caret geometry from the previous line: $immediate_state"

after_state="$(wait_for_current_caret)"
jq -e --argjson before "$before_state" \
  '.liveCursorY > $before.liveCursorY' <<<"$after_state" >/dev/null || \
  fail "Enter did not move the rendered caret below test: $after_state"

grim "$ARTIFACT_DIR/jotpin-caret-after-test-enter.png"

sleep 0.6
[[ "$(<"$TEST_NOTE_PATH")" == "test" ]] || \
  fail "the saved note text before its trailing newline was not test"
[[ "$(tail -c 1 "$TEST_NOTE_PATH" | od -An -tuC | tr -d ' ')" == "10" ]] || \
  fail "Enter did not preserve the trailing newline in the saved note"

wtype a
typed_state="$(wait_for_typed_caret)"
jq -e --argjson empty "$after_state" \
  '((.liveCursorY - $empty.liveCursorY) | fabs) < 0.5' \
  <<<"$typed_state" >/dev/null || \
  fail "empty and populated second lines used different spacing: empty=$after_state typed=$typed_state"
grim "$ARTIFACT_DIR/jotpin-caret-after-test-enter-a.png"

wtype -k Return
wtype a
three_line_bottom_state="$(wait_for_three_line_bottom)"
wtype -M ctrl -k Home -m ctrl
three_line_top_state="$(wait_for_three_line_top)"

jq -e --argjson single "$before_state" \
  '((.liveCursorY - $single.liveCursorY) | fabs) < 0.5' \
  <<<"$three_line_top_state" >/dev/null || \
  fail "adding lines moved the first-line caret: single=$before_state multiline=$three_line_top_state"

jq -e --argjson first "$before_state" --argjson second "$typed_state" '
  (((.liveCursorY - $second.liveCursorY) -
    ($second.liveCursorY - $first.liveCursorY)) | fabs) < 0.5
' <<<"$three_line_bottom_state" >/dev/null || \
  fail "paragraph lines used inconsistent caret advances: first=$before_state second=$typed_state third=$three_line_bottom_state"

grim "$ARTIFACT_DIR/jotpin-three-line-caret-top.png"
wtype -M ctrl -k End -m ctrl
wait_for_three_line_bottom >/dev/null
grim "$ARTIFACT_DIR/jotpin-three-line-caret-bottom.png"

printf 'PASS: Enter moves the source cursor to line two\n'
printf 'PASS: Enter never exposes the previous line caret geometry\n'
printf 'PASS: settled caret matches the rendered second-line geometry\n'
printf 'PASS: empty and populated second lines use identical spacing\n'
printf 'PASS: multiline paragraph carets stay centered from first to last line\n'
printf 'PASS: focused Enter artifact captured in %s\n' "$ARTIFACT_DIR"
