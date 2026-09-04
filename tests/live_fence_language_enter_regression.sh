#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-fence-language-enter-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-fence-language-enter.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/fence-language-enter.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}' | tail -n 1
}

editor_state() {
  omarchy-shell shell call dev.jotpin editorCommandState '{}' | tail -n 1
}

wait_for_focus() {
  local active state
  for _attempt in $(seq 1 120); do
    active="$(hyprctl activewindow -j)"
    state="$(editor_state)"
    if jq -e '.class == "org.quickshell" and
        (.title | startswith("JotPin "))' <<<"$active" >/dev/null 2>&1 &&
        jq -e '.editorActiveFocus' <<<"$state" >/dev/null 2>&1; then
      return
    fi
    sleep 0.025
  done
  fail "JotPin did not receive compositor and editor focus: active=$active editor=$state"
}

wait_for_state() {
  local expected_cursor="$1"
  local expected_length="$2"
  local attempt state
  for attempt in $(seq 1 120); do
    state="$(caret_state)"
    if jq -e --argjson cursor "$expected_cursor" --argjson length "$expected_length" '
      .cursorPosition == $cursor and .sourceLength == $length and
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "fence-language caret did not settle at $expected_cursor/$expected_length: $state"
}

wait_for_text() {
  local expected_text="$1"
  local attempt state
  for attempt in $(seq 1 120); do
    state="$(editor_state)"
    if jq -e --arg text "$expected_text" \
        '.text == $text and .editorActiveFocus' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "editor source did not settle to the expected text: expected=$expected_text state=$state"
}

cleanup() {
  wtype -p BackSpace >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell hyprctl grim wtype jq; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
: > "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
wait_for_focus

wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
wtype -d 30 -- '```'
wait_for_state 3 9 >/dev/null
wtype -d 30 -- javascript
before_state="$(wait_for_state 13 19)"
grim "$ARTIFACT_DIR/before-enter.png"

wtype -k Return
after_state="$(wait_for_state 14 19)"
grim "$ARTIFACT_DIR/after-one-enter.png"

jq -e '.sourceLine == 1 and .targetBlockType == "code" and
    .renderedCursorY > 0 and
    ((.liveCursorY - .renderedCursorY) | fabs) < 0.5' \
  <<<"$after_state" >/dev/null ||
  fail "one physical Enter did not visibly enter the first code row: before=$before_state after=$after_state"

wtype x
typed_state="$(wait_for_state 15 20)"
grim "$ARTIFACT_DIR/after-one-enter-x.png"
jq -e --argjson after "$after_state" '
  .sourceLine == 1 and .targetBlockType == "code" and
  ((.liveCursorY - $after.liveCursorY) | fabs) < 0.5
' <<<"$typed_state" >/dev/null ||
  fail "typing after one physical Enter did not stay on the first code row: after=$after_state typed=$typed_state"
wait_for_text $'```javascript\nx\n```\n' >/dev/null

wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
wait_for_text "" >/dev/null
wtype -d 30 -- '```'
wait_for_state 3 9 >/dev/null
wtype -d 30 -- js
wait_for_state 5 11 >/dev/null
wtype -k Return
wait_for_state 6 11 >/dev/null
wtype -d 30 -- fasdf
sleep 0.15
body_state="$(editor_state)"
grim "$ARTIFACT_DIR/after-js-enter-fasdf.png"
jq -e '.text == "```js\nfasdf\n```\n" and .cursorPosition == 11' \
  <<<"$body_state" >/dev/null ||
  fail "typing code placed the generated closer on the body line: $body_state"
wtype -k Down
escape_state="$(wait_for_state 16 16)"
jq -e '.sourceLine == 3 and .targetBlockType == "blank" and
    .liveCursorSourcePosition == 16' <<<"$escape_state" >/dev/null ||
  fail "Down could not escape to the editable line after the closing fence: $escape_state"
wtype -d 30 -- outside
wait_for_text $'```js\nfasdf\n```\noutside' >/dev/null
grim "$ARTIFACT_DIR/after-code-block-escape.png"

wtype -M ctrl -k A -m ctrl
wtype -k BackSpace
wait_for_text "" >/dev/null
wtype -d 30 -- '```'
wait_for_state 3 9 >/dev/null
wtype -d 30 -- js
wait_for_state 5 11 >/dev/null
wtype -k Return
wait_for_state 6 11 >/dev/null
wtype -d 30 -- '{'
wtype -d 30 -- fasdf
wait_for_text $'```js\n{fasdf}\n```\n' >/dev/null
grim "$ARTIFACT_DIR/before-held-backspace.png"

malformed_state=""
wtype -P BackSpace -s 900 -p BackSpace &
backspace_pid=$!
while kill -0 "$backspace_pid" >/dev/null 2>&1; do
  repeat_state="$(editor_state)"
  if ! jq -e '.text == "" or (.text | startswith("```"))' \
      <<<"$repeat_state" >/dev/null 2>&1; then
    malformed_state="$repeat_state"
    break
  fi
  sleep 0.008
done
wait "$backspace_pid"
deleted_state="$(editor_state)"
deleted_caret="$(caret_state)"
grim "$ARTIFACT_DIR/after-held-backspace.png"
[[ -z "$malformed_state" ]] ||
  fail "held Backspace exposed a partial fence or orphaned code closer: $malformed_state"
jq -e '.text == "" and .cursorPosition == 0 and .editorActiveFocus' \
  <<<"$deleted_state" >/dev/null ||
  fail "held Backspace did not remove the complete generated fence: editor=$deleted_state caret=$deleted_caret"

printf 'PASS: one compositor-routed Enter leaves the fence-language header\n'
printf 'PASS: typing after one Enter lands on the first visible code row\n'
printf 'PASS: typed code stays on its own line before the generated closer\n'
printf 'PASS: Down escapes to the editable line after the closing fence\n'
printf 'PASS: held Backspace never exposes a partial generated fence opener\n'
printf 'PASS: held Backspace removes the language and complete generated fence\n'
printf 'PASS: focused fence-language artifacts captured in %s\n' "$ARTIFACT_DIR"
