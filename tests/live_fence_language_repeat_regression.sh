#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-fence-language-repeat-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-fence-language-repeat.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/fence-language-repeat.md"

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

document_state() {
  omarchy-shell shell call dev.jotpin renderedDocumentStateForTests '{}' | tail -n 1
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

wait_for_current_caret() {
  local state document
  for _attempt in $(seq 1 200); do
    state="$(caret_state)"
    document="$(document_state)"
    if jq -e '.liveCursorVisible and
        .liveCursorSourcePosition == .cursorPosition and
        .layoutReady and .layoutSourceMatches and .layoutCursorMatches' \
        <<<"$state" >/dev/null 2>&1 &&
        jq -e '.layoutReady and .layoutMatches and
          (.parsePending | not) and (.parseInFlight | not)' \
          <<<"$document" >/dev/null 2>&1; then
      sleep 0.15
      local confirmed_state confirmed_document
      confirmed_state="$(caret_state)"
      confirmed_document="$(document_state)"
      if jq -e --argjson prior "$state" '
          .liveCursorVisible and
          .liveCursorSourcePosition == .cursorPosition and
          .cursorPosition == $prior.cursorPosition and
          .sourceLength == $prior.sourceLength and
          ((.liveCursorY - $prior.liveCursorY) | fabs) <= 1 and
          .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
          .codeHighlightPendingCount == 0' \
          <<<"$confirmed_state" >/dev/null 2>&1 &&
          jq -e '.layoutReady and .layoutMatches and
            (.parsePending | not) and (.parseInFlight | not)' \
            <<<"$confirmed_document" >/dev/null 2>&1; then
        printf '%s\n' "$confirmed_state"
        return
      fi
    fi
    sleep 0.02
  done
  fail "the fence-language caret did not settle: $state"
}

wait_for_fence_source() {
  local state
  for _attempt in $(seq 1 200); do
    state="$(editor_state)"
    if jq -e '.text == "```\n\n```\n" and .editorActiveFocus' \
        <<<"$state" >/dev/null 2>&1; then
      return
    fi
    sleep 0.02
  done
  fail "the disposable fence fixture did not load: $state"
}

observe_held_language_key() {
  local key="$1"
  local label="$2"
  local expected_y="$3"
  local hold_ms="$4"
  local observations="$TEST_TMP_DIR/$label.lengths"
  local wtype_pid editor caret document visible_count bad_state=""
  : > "$observations"

  wtype -P "$key" -s "$hold_ms" -p "$key" &
  wtype_pid=$!
  while kill -0 "$wtype_pid" >/dev/null 2>&1; do
    editor="$(editor_state)"
    caret="$(caret_state)"
    document="$(document_state)"
    if jq -e --argjson y "$expected_y" --argjson position \
        "$(jq -r '.cursorPosition' <<<"$editor")" '
          .liveCursorVisible and .sourceLine == 0 and
          .liveCursorSourcePosition == $position and
          ((.liveCursorY - $y) | fabs) <= 1
        ' <<<"$caret" >/dev/null 2>&1 &&
        jq -e --argjson editor "$editor" '
          .layoutReady and .layoutMatches and
          .layoutSourceText == $editor.text and
          .documentSourceText == $editor.text
        ' <<<"$document" >/dev/null 2>&1; then
      jq -r '.sourceLength' <<<"$caret" >> "$observations"
    elif jq -e --argjson position "$(jq -r '.cursorPosition' <<<"$editor")" '
          .liveCursorVisible and .liveCursorSourcePosition == $position
        ' <<<"$caret" >/dev/null 2>&1; then
      bad_state="editor=$editor caret=$caret document=$document"
      break
    fi
    sleep 0.008
  done
  wait "$wtype_pid"

  [[ -z "$bad_state" ]] ||
    fail "$label moved or exposed a stale rendered revision while held (expected liveCursorY=$expected_y): $bad_state"
  visible_count="$(sort -nu "$observations" | sed '/^$/d' | wc -l)"
  if (( visible_count < 3 )); then
    fail "$label exposed only $visible_count intermediate revisions while held; observations=$(tr '\n' ',' < "$observations") finalCaret=$(caret_state) finalDocument=$(document_state)"
  fi
  wait_for_current_caret >/dev/null
  printf 'PASS: %s exposed %s current rendered revisions while held\n' \
    "$label" "$visible_count"
}

cleanup() {
  wtype -p z -p BackSpace >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell hyprctl grim wtype jq sort sed wc tr; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
printf '```\n\n```\n' > "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
wait_for_focus
wait_for_fence_source
wtype -M ctrl -k Home -m ctrl
wtype -k Right -k Right -k Right
initial_state="$(wait_for_current_caret)"
initial_y="$(jq -r '.liveCursorY' <<<"$initial_state")"

observe_held_language_key z language-held-letter "$initial_y" 700
grim "$ARTIFACT_DIR/after-held-letter.png"

# Leave enough language characters for Backspace repeat to remain inside the
# header for the whole observation interval.
wtype -d 4 -- zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
wait_for_current_caret >/dev/null
observe_held_language_key BackSpace language-held-backspace "$initial_y" 450
grim "$ARTIFACT_DIR/after-held-backspace.png"

final_state="$(wait_for_current_caret)"
jq -e --argjson y "$initial_y" '
  .sourceLine == 0 and .targetBlockType == "code" and
  ((.liveCursorY - $y) | fabs) <= 1
' <<<"$final_state" >/dev/null ||
  fail "the reconciled language caret left its header row: initial=$initial_state final=$final_state"

printf 'PASS: fence-language typing and Backspace keep one stable caret row\n'
printf 'PASS: focused fence-language repeat artifacts captured in %s\n' "$ARTIFACT_DIR"
