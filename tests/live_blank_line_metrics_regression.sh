#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-blank-metrics-artifacts}"
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-blank-metrics.XXXXXX)"
readonly LEADING_NOTE_PATH="$TEST_TMP_DIR/leading-blank-caret.md"
readonly LIST_NOTE_PATH="$TEST_TMP_DIR/list-blank-caret.md"

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
      .liveCursorVisible and
      .liveCursorSourcePosition == $position and
      .layoutReady and
      .layoutSourceMatches and
      .layoutCursorMatches and
      ((.liveCursorY - .renderedCursorY) | fabs) < 0.5
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "caret did not settle at source position $expected_position: $state"
}

open_at_position() {
  local path="$1"
  local position="$2"
  local step
  omarchy-shell shell summon dev.jotpin \
    "{\"mode\":\"center\",\"path\":\"$path\"}" >/dev/null
  sleep 1
  wtype -M ctrl -k Home -m ctrl
  for step in $(seq 1 "$position"); do
    wtype -k Right
    sleep 0.02
  done
  wait_for_position "$position"
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$LEADING_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin closeFile "$LIST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell grim wtype jq sha256sum; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
cp -- "$ROOT_DIR/tests/fixtures/leading-blank-caret.md" "$LEADING_NOTE_PATH"
cp -- "$ROOT_DIR/tests/fixtures/list-blank-caret.md" "$LIST_NOTE_PATH"
leading_hash_before="$(sha256sum "$LEADING_NOTE_PATH" | cut -d' ' -f1)"
list_hash_before="$(sha256sum "$LIST_NOTE_PATH" | cut -d' ' -f1)"

leading_blank_state="$(open_at_position "$LEADING_NOTE_PATH" 0)"
grim "$ARTIFACT_DIR/jotpin-leading-blank-caret.png"
leading_first_state="$(open_at_position "$LEADING_NOTE_PATH" 1)"
leading_second_state="$(open_at_position "$LEADING_NOTE_PATH" 6)"

jq -e --argjson first "$leading_first_state" '
  .targetBlockType == "blank" and
  $first.targetBlockType == "paragraph" and
  (((.liveCursorHeight - $first.liveCursorHeight) | fabs) < 0.5) and
  (((($first.liveCursorY - .liveCursorY) -
    (($first.layoutMetrics | map(select(.type == "paragraph")) | .[0].lineAdvance))) | fabs) < 1.5)
' <<<"$leading_blank_state" >/dev/null || \
  fail "leading blank row did not use the normal body line advance: blank=$leading_blank_state first=$leading_first_state"

jq -e --argjson first "$leading_first_state" '
  .targetBlockType == "paragraph" and
  (((.liveCursorY - $first.liveCursorY) -
    (($first.layoutMetrics | map(select(.type == "paragraph")) | .[0].lineAdvance))) | fabs) < 0.5
' <<<"$leading_second_state" >/dev/null || \
  fail "leading fixture text rows used inconsistent line spacing: first=$leading_first_state second=$leading_second_state"

list_state="$(open_at_position "$LIST_NOTE_PATH" 0)"
list_blank_state="$(open_at_position "$LIST_NOTE_PATH" 7)"
grim "$ARTIFACT_DIR/jotpin-list-blank-caret.png"
list_text_state="$(open_at_position "$LIST_NOTE_PATH" 8)"

jq -e --argjson list "$list_state" --argjson text "$list_text_state" '
  .targetBlockType == "blank" and
  (((.liveCursorY - (($list.liveCursorY + $text.liveCursorY) / 2)) | fabs) < 0.5) and
  (((.liveCursorHeight - $text.liveCursorHeight) | fabs) < 0.5)
' <<<"$list_blank_state" >/dev/null || \
  fail "list-separated blank row was not centered between its rendered neighbors: list=$list_state blank=$list_blank_state text=$list_text_state"

leading_hash_after="$(sha256sum "$LEADING_NOTE_PATH" | cut -d' ' -f1)"
list_hash_after="$(sha256sum "$LIST_NOTE_PATH" | cut -d' ' -f1)"
[[ "$leading_hash_before" == "$leading_hash_after" ]] || \
  fail "leading blank caret fixture changed during navigation"
[[ "$list_hash_before" == "$list_hash_after" ]] || \
  fail "list blank caret fixture changed during navigation"

printf 'PASS: leading blank caret uses one normal body line advance\n'
printf 'PASS: leading fixture text rows retain one consistent line advance\n'
printf 'PASS: list-separated blank caret is centered between rendered neighbors\n'
printf 'PASS: blank-row caret metrics preserve both fixture sources\n'
printf 'PASS: focused blank-line metrics artifacts captured in %s\n' "$ARTIFACT_DIR"
