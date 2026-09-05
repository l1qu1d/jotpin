#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-list-continuation-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-list-continuation.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/list-continuation.md"
readonly BETWEEN_NOTE_PATH="$TEST_TMP_DIR/list-between-existing.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

wait_for_state() {
  local expected_position="$1"
  local expected_length="$2"
  local expected_line="$3"
  local expected_block="$4"
  local attempt state
  for attempt in $(seq 1 80); do
    state="$(caret_state)"
    if jq -e \
      --argjson position "$expected_position" \
      --argjson length "$expected_length" \
      --argjson line "$expected_line" \
      --arg block "$expected_block" \
      '
      .cursorPosition == $position and .sourceLength == $length and
      .sourceLine == $line and .targetBlockType == $block and
      .liveCursorSourcePosition == $position and .liveCursorHeight > 0 and
      .renderedCursorY >= 0 and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.025
  done
  fail "list continuation state did not settle: $state"
}

wait_for_clean_save() {
  local attempt state
  for attempt in $(seq 1 120); do
    state="$(omarchy-shell shell call dev.jotpin persistenceState '{}')"
    if jq -e '
      .statusText == "Saved" and .dirty == false and
      .pendingSave == false and .noteSaveInFlight == false
    ' <<<"$state" >/dev/null; then
      return
    fi
    sleep 0.025
  done
  fail "list continuation save did not settle: $state"
}

cleanup() {
  omarchy-shell shell call dev.jotpin closeFile "$TEST_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin closeFile "$BETWEEN_NOTE_PATH" \
    >/dev/null 2>&1 || true
  omarchy-shell shell call dev.jotpin close '{}' >/dev/null 2>&1 || true
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in omarchy-shell grim wtype jq; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -p -- "$ARTIFACT_DIR"
if [[ "${1:-}" != "between-existing" ]]; then
  printf '' > "$TEST_NOTE_PATH"
  omarchy-shell shell summon dev.jotpin \
    "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
  sleep 1
  wtype -M ctrl -k A -m ctrl
  wtype -k BackSpace
  sleep 0.1

  wtype -- -
  sleep 0.1
  wtype -d 25 -- 'task one'
  wtype -k Return
  first_continuation="$(wait_for_state 13 13 1 list)"
  grim "$ARTIFACT_DIR/jotpin-list-continuation-created.png"

  wtype -k Backspace
  space_removed_state="$(wait_for_state 10 10 0 list)"
  grim "$ARTIFACT_DIR/jotpin-list-continuation-space-removed.png"
  backspace_state="$space_removed_state"
  grim "$ARTIFACT_DIR/jotpin-list-continuation-backspace.png"

  wtype -k Return
  wtype -d 25 -- 'task two'
  wtype -k Return
  wait_for_state 24 24 2 list >/dev/null
  wtype -k Return
  exit_state="$(wait_for_state 22 22 2 blank)"
  grim "$ARTIFACT_DIR/jotpin-list-continuation-exited.png"

  wait_for_clean_save
  [[ "$(<"$TEST_NOTE_PATH")" == $'- task one\n- task two' ]] || \
    fail "saved list did not contain exactly two completed bullets"
  [[ "$(tail -c 1 "$TEST_NOTE_PATH" | od -An -tuC | tr -d ' ')" == "10" ]] || \
    fail "exiting the list did not preserve the final blank source line"
fi

first_existing_item='- JotPin autosaves after a short pause; use `Ctrl+S` to save immediately.'
following_existing_item='- Use Side, Center, or Full Screen to match the way you are working.'
if [[ "${1:-}" == "between-existing-blank" ||
    "${1:-}" == "between-existing-blank-direct" ]]; then
  printf '%s\n\n\n\n%s\n' "$first_existing_item" "$following_existing_item" \
    >"$BETWEEN_NOTE_PATH"
else
  printf '%s\n%s\n' "$first_existing_item" "$following_existing_item" \
    >"$BETWEEN_NOTE_PATH"
fi
between_initial_length="$(wc -c <"$BETWEEN_NOTE_PATH")"
between_first_end="${#first_existing_item}"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"side\",\"path\":\"$BETWEEN_NOTE_PATH\"}" >/dev/null
sleep 1
wtype -M ctrl -k Home -m ctrl
wtype -k End
wtype -k Down
wtype -k End
if [[ "${1:-}" == "between-existing-blank" ||
    "${1:-}" == "between-existing-blank-direct" ]]; then
  wtype -k Right
  between_initial_cursor=$((between_first_end + 1))
  wait_for_state "$between_initial_cursor" "$between_initial_length" 1 list \
    >/dev/null
else
  wait_for_state "$between_first_end" "$between_initial_length" 0 list \
    >/dev/null
fi
if [[ "${1:-}" == "between-existing-blank-direct" ]]; then
  direct_result="$(omarchy-shell shell call dev.jotpin handleListReturn '{}')"
  [[ "$direct_result" == "true" ]] || \
    fail "live handleListReturn rejected the stranded blank line: $direct_result"
else
  wtype -k Return
fi
between_cursor=$((between_first_end + 3))
if [[ "${1:-}" == "between-existing-blank" ||
    "${1:-}" == "between-existing-blank-direct" ]]; then
  between_length=$between_initial_length
else
  between_length=$((between_initial_length + 3))
fi
wait_for_state "$between_cursor" "$between_length" 1 list >/dev/null
grim "$ARTIFACT_DIR/jotpin-list-between-existing-created.png"
wait_for_clean_save
if [[ "${1:-}" == "between-existing-blank" ||
    "${1:-}" == "between-existing-blank-direct" ]]; then
  [[ "$(<"$BETWEEN_NOTE_PATH")" == \
      "$first_existing_item"$'\n- \n'"$following_existing_item" ]] || \
    fail "Enter did not recover the bullet without hidden blank rows"
else
  [[ "$(<"$BETWEEN_NOTE_PATH")" == \
      "$first_existing_item"$'\n- \n'"$following_existing_item" ]] || \
    fail "Enter before an existing item did not persist the inserted bullet"
fi

if [[ "${1:-}" != "between-existing" ]]; then
  printf 'PASS: Enter after a populated bullet creates the next marker\n'
fi
printf 'PASS: Enter after a wrapped bullet inserts before an existing item\n'
printf 'PASS: Preview Backspace removes an empty bullet row as one semantic edit\n'
printf 'PASS: Enter on an empty bullet removes the marker and exits the list\n'
printf 'PASS: list continuation preserves the completed Markdown source\n'
printf 'PASS: focused list artifacts captured in %s\n' "$ARTIFACT_DIR"
