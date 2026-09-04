#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-navigation-artifacts}"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-navigation.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/vertical-navigation.md"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

caret_state() {
  omarchy-shell shell call dev.jotpin caretState '{}'
}

wait_for_target() {
  local expected_line="$1"
  local expected_item="$2"
  local attempt state
  for attempt in $(seq 1 60); do
    state="$(caret_state)"
    if jq -e --argjson line "$expected_line" --argjson item "$expected_item" '
      .liveCursorVisible and
      .liveCursorSourcePosition == .cursorPosition and
      .layoutReady and .layoutSourceMatches and .layoutCursorMatches and
      .sourceLine == $line and .targetBlockType == "list" and
      .targetItemIndex == $item
    ' <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.02
  done
  fail "caret did not settle on list item $expected_item: $state"
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
cp -- "$ROOT_DIR/tests/fixtures/vertical-navigation.md" "$TEST_NOTE_PATH"
omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1

wtype -M ctrl -k Home -m ctrl
wtype -k End
sleep 0.05

# Down from the end of `test` must land on `hi`, which is source line 1 and
# rendered list item 0. There is no blank source line to target.
wtype -k Down
first_item_state="$(wait_for_target 1 0)"
jq -e '.cursorPosition == 9' <<<"$first_item_state" >/dev/null || \
  fail "Down did not preserve the expected visual column on hi: $first_item_state"
grim "$ARTIFACT_DIR/jotpin-arrow-down-to-hi.png"

# Rapid Up/Down movement previously left the caret missing or in the block
# gap. Every completed Down must return to the first list item.
for cycle in $(seq 1 20); do
  wtype -k Up
  sleep 0.01
  wtype -k Down
  wait_for_target 1 0 >/dev/null
done

wtype -k Down
second_item_state="$(wait_for_target 2 1)"
jq -e '.cursorPosition == 14' <<<"$second_item_state" >/dev/null || \
  fail "second Down did not preserve visual column 4 on the final list item: $second_item_state"
grim "$ARTIFACT_DIR/jotpin-arrow-down-to-second-item.png"

printf 'PASS: Down from the paragraph lands on hi with a visible caret\n'
printf 'PASS: rapid vertical navigation never loses the list caret\n'
printf 'PASS: focused navigation artifacts captured in %s\n' "$ARTIFACT_DIR"
