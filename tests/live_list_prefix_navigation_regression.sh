#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ARTIFACT_DIR="${JOTPIN_ARTIFACT_DIR:-/tmp/jotpin-list-prefix-artifacts}"
readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-list-prefix.XXXXXX)"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/list-prefix.md"

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
      .layoutCursorMatches
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
  for step in $(seq 1 "$count"); do
    wtype -k Right
    sleep 0.02
  done
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
cp -- "$ROOT_DIR/tests/fixtures/list-caret-single-line.md" "$TEST_NOTE_PATH"
before_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"

omarchy-shell shell summon dev.jotpin \
  "{\"mode\":\"center\",\"path\":\"$TEST_NOTE_PATH\"}" >/dev/null
sleep 1
wtype -M ctrl -k Home -m ctrl
wait_for_position 0 >/dev/null
# `- hi` starts at source position 6. Live horizontal navigation treats the
# marker as one visual boundary, so seven Right presses reach the first letter
# at source position 8.
move_right 7
first_state="$(wait_for_position 8)"
grim "$ARTIFACT_DIR/jotpin-list-prefix-first-letter.png"

wtype -k Left
marker_state="$(wait_for_position 6)"
jq -e --argjson first "$first_state" '
  .targetBlockType == "list" and .targetItemIndex == 0 and
  .liveCursorX < $first.liveCursorX
' <<<"$marker_state" >/dev/null || \
  fail "Left from the first list letter did not move to the visible marker boundary: first=$first_state marker=$marker_state"

wtype -k Right
roundtrip_state="$(wait_for_position 8)"
jq -e --argjson first "$first_state" '
  .liveCursorX == $first.liveCursorX and
  .targetBlockType == "list" and .targetItemIndex == 0
' <<<"$roundtrip_state" >/dev/null || \
  fail "Right from the marker boundary did not return to the first list letter: first=$first_state roundtrip=$roundtrip_state"

# Reproduce the reported three-Left / three-Right sequence. Each movement
# must traverse a visible row or the visible marker/text boundary; the hidden
# `- ` source prefix must not absorb three arrows at one screen column.
wtype -k Left
wait_for_position 6 >/dev/null
wtype -k Left
wait_for_position 5 >/dev/null
wtype -k Left
wait_for_position 4 >/dev/null
wtype -k Right
wait_for_position 5 >/dev/null
wtype -k Right
three_right_marker_state="$(wait_for_position 6)"
wtype -k Right
three_right_text_state="$(wait_for_position 8)"

jq -e --argjson marker "$three_right_marker_state" '
  .liveCursorX > $marker.liveCursorX
' <<<"$three_right_text_state" >/dev/null || \
  fail "three-Right sequence still crossed a hidden prefix without visible movement: marker=$three_right_marker_state text=$three_right_text_state"

grim "$ARTIFACT_DIR/jotpin-list-prefix-roundtrip.png"
after_hash="$(sha256sum "$TEST_NOTE_PATH" | cut -d' ' -f1)"
[[ "$before_hash" == "$after_hash" ]] || \
  fail "horizontal list-prefix navigation changed the Markdown source"

printf 'PASS: Left from the first bullet letter reaches the visible marker boundary\n'
printf 'PASS: Right from the marker boundary returns to the first bullet letter\n'
printf 'PASS: three-Left / three-Right navigation has no hidden-prefix stall\n'
printf 'PASS: list-prefix navigation preserves the Markdown source\n'
printf 'PASS: focused list-prefix artifacts captured in %s\n' "$ARTIFACT_DIR"
