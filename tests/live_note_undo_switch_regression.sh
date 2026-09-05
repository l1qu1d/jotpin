#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-live-note-undo.XXXXXX)"
readonly FIRST_NOTE_PATH="$TEST_TMP_DIR/first.md"
readonly SECOND_NOTE_PATH="$TEST_TMP_DIR/second.md"
readonly MARKER="x"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

editor_state() {
  omarchy-shell shell call dev.jotpin editorCommandState '{}' | tail -n 1
}

wait_for_jotpin_focus() {
  local description="$1"
  local attempt active=""
  for attempt in $(seq 1 120); do
    active="$(hyprctl activewindow -j)"
    if jq -e '
      .class == "org.quickshell" and (.title | startswith("JotPin "))
    ' <<<"$active" >/dev/null 2>&1; then
      return
    fi
    sleep 0.025
  done
  fail "$description: $active"
}

wait_for_state() {
  local jq_expression="$1"
  local description="$2"
  local attempt state=""
  for attempt in $(seq 1 120); do
    state="$(editor_state)"
    if jq -e "$jq_expression" <<<"$state" >/dev/null 2>&1; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "$description: $state"
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$FIRST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin closeFile "$SECOND_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell hyprctl wtype jq cmp; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$FIRST_NOTE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/source-preservation.md" "$SECOND_NOTE_PATH"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$FIRST_NOTE_PATH\"}" >/dev/null
wait_for_jotpin_focus 'first disposable note window did not receive compositor focus'
wait_for_state \
  '.text == "base\n" and .editorActiveFocus and (.canUndo | not)' \
  'first disposable note did not become focused' >/dev/null

wtype -M ctrl -k End -m ctrl
wtype "$MARKER"
wait_for_state \
  '.text == "base\nx" and .editorActiveFocus and .canUndo' \
  'real typing did not create persistent history' >/dev/null

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$SECOND_NOTE_PATH\"}" >/dev/null
wait_for_jotpin_focus 'second disposable note window did not retain compositor focus'
wait_for_state \
  '.text | startswith("# Source preservation\n")' \
  'second disposable note did not load' >/dev/null

wtype -M ctrl -k left -m ctrl
wait_for_state \
  '.text == "base\nx" and .editorActiveFocus and .canUndo' \
  'real Ctrl+Left did not switch to the previous note' >/dev/null

wtype -M ctrl -k right -m ctrl
wait_for_state \
  '.text | startswith("# Source preservation\n")' \
  'real Ctrl+Right did not switch to the next note' >/dev/null

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$FIRST_NOTE_PATH\"}" >/dev/null
wait_for_jotpin_focus 'restored first note window did not retain compositor focus'
wait_for_state \
  '.text == "base\nx" and .editorActiveFocus and .canUndo' \
  'first note did not restore its focus and undo history' >/dev/null

wtype -M ctrl -k z -m ctrl
wait_for_state \
  '.text == "base\n" and .editorActiveFocus and .canRedo' \
  'real Ctrl+Z did not undo after switching notes' >/dev/null
wait_for_state \
  '(.dirty | not) and .text == "base\n" and .canRedo' \
  'undone source did not finish saving' >/dev/null

cmp -s "$ROOT_DIR/tests/fixtures/persistence-base.md" "$FIRST_NOTE_PATH" ||
  fail 'saved first note did not return to its original bytes'

printf 'PASS: real typing creates per-note undo history\n'
printf 'PASS: real Ctrl+Left and Ctrl+Right switch between note tabs\n'
printf 'PASS: switching away and back restores that history\n'
printf 'PASS: a real Ctrl+Z chord undoes through the focused live editor\n'
printf 'PASS: the undone source is saved byte-for-byte\n'
