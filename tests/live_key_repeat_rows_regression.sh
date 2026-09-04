#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-key-repeat-rows-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-key-repeat-rows.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/key-repeat-rows.md"

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

wait_for_current_caret() {
  local state
  for _attempt in $(seq 1 160); do
    state="$(caret_state)"
    if jq -e '.liveCursorVisible and
        .liveCursorSourcePosition == .cursorPosition and
        .layoutReady and .layoutSourceMatches and .layoutCursorMatches' \
        <<<"$state" >/dev/null 2>&1; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "the live caret did not settle on the current source revision: $state"
}

clear_editor() {
  wtype -M ctrl -k A -m ctrl
  wtype -k BackSpace
  for _attempt in $(seq 1 80); do
    if jq -e '.text == "" and .cursorPosition == 0' \
        <<<"$(editor_state)" >/dev/null 2>&1; then
      return
    fi
    sleep 0.025
  done
  fail "the disposable editor did not clear: $(editor_state)"
}

observe_held_key_rows() {
  local key="$1"
  local label="$2"
  local required_block="$3"
  local observations="$TEST_TMP_DIR/$label.rows"
  local wtype_pid state visible_count
  : > "$observations"

  wtype -P "$key" -s 1100 -p "$key" &
  wtype_pid=$!
  while kill -0 "$wtype_pid" >/dev/null 2>&1; do
    state="$(caret_state)"
    if jq -e --arg block "$required_block" '
        .liveCursorVisible and
        .liveCursorSourcePosition == .cursorPosition and
        .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
        ($block == "any" or .targetBlockType == $block)
      ' <<<"$state" >/dev/null 2>&1; then
      jq -r '.sourceLine' <<<"$state" >> "$observations"
    fi
    sleep 0.012
  done
  wait "$wtype_pid"

  visible_count="$(sort -nu "$observations" | sed '/^$/d' | wc -l)"
  if (( visible_count < 3 )); then
    fail "$label updated only $visible_count visible source rows while held; observations=$(tr '\n' ',' < "$observations") final=$(caret_state)"
  fi
  wait_for_current_caret >/dev/null
  printf 'PASS: %s painted %s distinct rows while the key remained held\n' \
    "$label" "$visible_count"
}

cleanup() {
  wtype -p Return -p BackSpace >/dev/null 2>&1 || true
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
: > "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
wait_for_focus

clear_editor
wtype -d 25 -- start
wait_for_current_caret >/dev/null
observe_held_key_rows Return ordinary-held-enter any
grim "$ARTIFACT_DIR/ordinary-held-enter.png"
observe_held_key_rows BackSpace ordinary-held-backspace any
grim "$ARTIFACT_DIR/ordinary-held-backspace.png"

clear_editor
wtype -d 25 -- '```'
wtype -d 25 -- js
wtype -k Return
wtype -d 25 -- fasdf
wait_for_current_caret >/dev/null
observe_held_key_rows Return code-held-enter code
grim "$ARTIFACT_DIR/code-held-enter.png"
observe_held_key_rows BackSpace code-held-backspace code
grim "$ARTIFACT_DIR/code-held-backspace.png"

printf 'PASS: held Enter and Backspace repaint continuously in ordinary and code rows\n'
printf 'PASS: focused key-repeat artifacts captured in %s\n' "$ARTIFACT_DIR"
