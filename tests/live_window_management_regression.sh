#!/usr/bin/env bash
set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/lib/live_guard.sh"

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-window-management.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly TEST_HOME="$TEST_TMP_DIR/home"
readonly TEST_NOTE_PATH="$TEST_TMP_DIR/window-management.md"
readonly CENTER_TITLE="JotPin Window — window-management.md"
readonly SIDE_TITLE="JotPin Side top right — window-management.md"
readonly SPECIAL_FIXTURE_TITLE="JotPin special-workspace fixture"
readonly SPECIAL_WORKSPACE_NAME="jotpin-regression"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"
readonly FIXTURE_OUTPUT_PATH="$TEST_TMP_DIR/special-fixture.log"
quickshell_pid=""
fixture_pid=""
window_address=""
fixture_address=""
rule_loaded=false
special_workspace_open=false

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$OUTPUT_PATH" ]]; then
    sed -n '1,220p' "$OUTPUT_PATH" >&2
  fi
  exit 1
}

stop_test_window() {
  if [[ -n "$quickshell_pid" ]] && kill -0 "$quickshell_pid" 2>/dev/null; then
    kill "$quickshell_pid" 2>/dev/null || true
    wait "$quickshell_pid" 2>/dev/null || true
  fi
  quickshell_pid=""
  window_address=""
}

stop_fixture() {
  if [[ -n "$fixture_pid" ]] && kill -0 "$fixture_pid" 2>/dev/null; then
    kill "$fixture_pid" 2>/dev/null || true
    wait "$fixture_pid" 2>/dev/null || true
  fi
  fixture_pid=""
  fixture_address=""
}

close_special_workspace() {
  if [[ "$special_workspace_open" == true ]]; then
    hyprctl eval \
      "hl.dispatch(hl.dsp.workspace.toggle_special(\"$SPECIAL_WORKSPACE_NAME\"))" \
      >/dev/null 2>&1 || true
    special_workspace_open=false
  fi
}

cleanup() {
  stop_test_window
  close_special_workspace
  stop_fixture
  if [[ "$rule_loaded" == true ]]; then
    hyprctl reload >/dev/null 2>&1 || true
  fi
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell hyprctl jq rg mktemp cp ln mkdir kill sed; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -m 700 -p -- "$CONFIG_DIR/jotpin" "$TEST_HOME/.config/omarchy"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"
cp -- "$ROOT_DIR/JotPin.qml" "$ROOT_DIR/JotPinButton.qml" \
  "$ROOT_DIR/HostIntegration.qml" \
  "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  "$ROOT_DIR/EditorModel.js" "$ROOT_DIR/HtmlEntities.js" \
  "$ROOT_DIR/SpellcheckModel.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/markdown" \
  "$CONFIG_DIR/jotpin/spellcheck" "$CONFIG_DIR/jotpin/syntax"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/jotpin/markdown/"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.mjs" "$ROOT_DIR/spellcheck/DictionaryPart1.mjs" "$ROOT_DIR/spellcheck/DictionaryPart2.mjs" "$CONFIG_DIR/jotpin/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/jotpin/syntax/"
cp -- "$ROOT_DIR/tests/qml/live_window_management.qml" "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/tests/qml/special_workspace_fixture.qml" \
  "$CONFIG_DIR/special_workspace_fixture.qml"
cp -- "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_NOTE_PATH"
if [[ -f "$HOME/.config/omarchy/shell.toml" ]]; then
  cp -- "$HOME/.config/omarchy/shell.toml" \
    "$TEST_HOME/.config/omarchy/shell.toml"
fi

if ! rule_output="$(hyprctl eval \
    "dofile([[$ROOT_DIR/hypr/jotpin.lua]])" 2>&1)"; then
  fail "could not load the transient JotPin window rules: $rule_output"
fi
rule_loaded=true

launch_test_window() {
  local mode="$1"
  local title="$2"
  local toggle_maximized="${3:-0}"
  : >"$OUTPUT_PATH"
  HOME="$TEST_HOME" JOTPIN_TEST_NOTE="$TEST_NOTE_PATH" \
    JOTPIN_TEST_MODE="$mode" \
    JOTPIN_TEST_TOGGLE_MAXIMIZED="$toggle_maximized" \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1 &
  quickshell_pid="$!"

  for _ in $(seq 1 100); do
    window_address="$(hyprctl clients -j | jq -r --arg title "$title" \
      '.[] | select(.title == $title) | .address' | head -n 1)"
    [[ -n "$window_address" ]] && return
    sleep 0.05
  done
  fail "$mode JotPin window did not map"
}

launch_special_fixture() {
  : >"$FIXTURE_OUTPUT_PATH"
  HOME="$TEST_HOME" JOTPIN_TEST_SPECIAL_TITLE="$SPECIAL_FIXTURE_TITLE" \
    quickshell --no-duplicate --path "$CONFIG_DIR/special_workspace_fixture.qml" \
    >"$FIXTURE_OUTPUT_PATH" 2>&1 &
  fixture_pid="$!"

  for _ in $(seq 1 100); do
    fixture_address="$(hyprctl clients -j | jq -r --arg title \
      "$SPECIAL_FIXTURE_TITLE" \
      '.[] | select(.title == $title) | .address' | head -n 1)"
    [[ -n "$fixture_address" ]] && return
    sleep 0.05
  done
  fail 'special-workspace fixture did not map'
}

show_special_fixture() {
  hyprctl eval \
    "hl.dispatch(hl.dsp.window.move({ workspace = \"special:$SPECIAL_WORKSPACE_NAME\", follow = false, window = \"address:$fixture_address\" }))" \
    >/dev/null
  hyprctl eval \
    "hl.dispatch(hl.dsp.workspace.toggle_special(\"$SPECIAL_WORKSPACE_NAME\"))" \
    >/dev/null
  special_workspace_open=true
  hyprctl eval \
    "hl.dispatch(hl.dsp.focus({ window = \"address:$fixture_address\" }))" \
    >/dev/null

  for _ in $(seq 1 100); do
    local active_workspace="$(hyprctl activewindow -j |
      jq -r '.workspace.name // ""')"
    [[ "$active_workspace" == "special:$SPECIAL_WORKSPACE_NAME" ]] && return
    sleep 0.05
  done
  fail 'special-workspace fixture did not become active'
}

client_json() {
  hyprctl clients -j | jq -c --arg address "$window_address" \
    '.[] | select(.address == $address)'
}

wait_for_client() {
  local expression="$1"
  local state=""
  for _ in $(seq 1 100); do
    state="$(client_json)"
    if jq -e "$expression" <<<"$state" >/dev/null; then
      printf '%s\n' "$state"
      return
    fi
    sleep 0.05
  done
  fail "window state did not satisfy $expression: $state"
}

wait_for_output() {
  local pattern="$1"
  for _ in $(seq 1 100); do
    if rg -q "$pattern" "$OUTPUT_PATH"; then return
    fi
    sleep 0.05
  done
  fail "live harness did not report $pattern"
}

wait_for_icon_state() {
  local expected_active="$1"
  local expected_icon="$2"
  local state=""
  for _ in $(seq 1 100); do
    state="$(sed -n 's/.*JOTPIN_MAXIMIZE_PROBE: //p' \
      "$OUTPUT_PATH" | tail -n 1)"
    if [[ -n "$state" ]] && jq -e \
        --argjson active "$expected_active" --arg icon "$expected_icon" \
        '.active == $active and .pending == false and .icon == $icon' \
        <<<"$state" >/dev/null; then
      return
    fi
    sleep 0.05
  done
  fail "Full Screen icon did not settle to active=$expected_active icon=$expected_icon: $state"
}

dispatch_fullscreen_mode() {
  local mode="$1"
  local output=""
  if ! output="$(hyprctl eval \
      "hl.dispatch(hl.dsp.window.fullscreen({ mode = \"$mode\", window = \"address:$window_address\" }))" \
      2>&1)"; then
    fail "$mode action failed: $output"
  fi
}

launch_test_window window "$CENTER_TITLE"
normal_state="$(wait_for_client \
  '.floating == true and .fullscreen == 0 and .size == [750,583]')"
normal_size="$(jq -c '.size' <<<"$normal_state")"
printf '%s\n' \
  "PASS: centered JotPin opens floating at its theme-scaled size $normal_size"

fullscreen_binding="$(hyprctl binds -j | jq -c \
  '[.[] | select(.description == "Full screen" and .mouse == false)][-1]')"
[[ "$fullscreen_binding" != "null" ]] || fail "active Full screen binding was not found"
[[ "$(jq -r '.key' <<<"$fullscreen_binding")" != "null" ]] || \
  fail "active Full screen action has no keyboard binding"

dispatch_fullscreen_mode fullscreen
wait_for_client '.fullscreen != 0' >/dev/null
dispatch_fullscreen_mode fullscreen
restored_state="$(wait_for_client ".fullscreen == 0 and .size == $normal_size")"
[[ "$(jq -c '.size' <<<"$restored_state")" == "$normal_size" ]] || \
  fail "centered JotPin did not restore its previous size"
printf '%s\n' 'PASS: centered JotPin fullscreen restores its previous size'
stop_test_window

launch_test_window side "$SIDE_TITLE" 1
side_state="$(wait_for_client '.floating == true and .fullscreen == 0')"
wait_for_icon_state false '󰘖'
side_size="$(jq -c '.size' <<<"$side_state")"
side_monitor_id="$(jq -r '.monitor' <<<"$side_state")"
monitor_state="$(hyprctl monitors -j | jq -c --argjson id "$side_monitor_id" \
  '.[] | select(.id == $id)')"
[[ -n "$monitor_state" ]] || fail "could not resolve Side's monitor"
if ! jq -e --argjson monitor "$monitor_state" \
    '(.at[0] + .size[0]) ==
       ($monitor.x + ($monitor.width / $monitor.scale)) and
     .at[1] == ($monitor.y + $monitor.reserved[1])' \
    <<<"$side_state" >/dev/null; then
  fail "Side did not open in the monitor's top-right work area: $side_state"
fi
[[ "$(hyprctl getprop "address:$window_address" border_size)" == "0" ]] || \
  fail "Side retained a compositor border"
[[ "$(hyprctl getprop "address:$window_address" no_shadow)" == "true" ]] || \
  fail "Side retained a floating-window shadow"
printf '%s\n' \
  'PASS: Side opens borderless in the top-right work area instead of behind the bar'

wait_for_client '.fullscreen == 1' >/dev/null
wait_for_output 'JOTPIN_MAXIMIZE_PROBE:'
wait_for_icon_state true '󰘕'
printf '%s\n' \
  'PASS: the JotPin expand control invokes Hyprland Full width mode'

dispatch_fullscreen_mode maximized
wait_for_client ".fullscreen == 0 and .size == $side_size" >/dev/null
wait_for_icon_state false '󰘖'
printf '%s\n' \
  'PASS: the JotPin expand control restores the Side drawer'

maximized_binding="$(hyprctl binds -j | jq -c \
  '[.[] | select(.description == "Full width" and .mouse == false)][-1]')"
[[ "$maximized_binding" != "null" ]] || fail "active Full width binding was not found"
[[ "$(jq -r '.key' <<<"$maximized_binding")" != "null" ]] || \
  fail "active Full width action has no keyboard binding"

dispatch_fullscreen_mode maximized
wait_for_client '.fullscreen != 0' >/dev/null
dispatch_fullscreen_mode maximized
wait_for_client ".fullscreen == 0 and .size == $side_size" >/dev/null
printf '%s\n' \
  'PASS: the active Full width action controls Side and restores its drawer size'

side_width="$(jq -r '.[0]' <<<"$side_size")"
side_height="$(jq -r '.[1]' <<<"$side_size")"
requested_width="$((side_width + 80))"
if ! resize_output="$(hyprctl eval \
    "hl.dispatch(hl.dsp.window.resize({ x = $requested_width, y = $((side_height - 80)), window = \"address:$window_address\" }))" \
    2>&1)"; then
  fail "Side native resize failed: $resize_output"
fi
wait_for_client ".size[0] == $requested_width and .size[1] == $side_height" >/dev/null
printf '%s\n' 'PASS: Side accepts horizontal resizing while preserving monitor height'

stop_test_window
launch_special_fixture
show_special_fixture
launch_test_window side "$SIDE_TITLE"
special_jotpin_state="$(wait_for_client \
  '.workspace.name == "special:jotpin-regression"')"
fixture_special_state="$(hyprctl clients -j | jq -c --arg address "$fixture_address" \
  '.[] | select(.address == $address)')"
[[ "$(jq -r '.workspace.name' <<<"$fixture_special_state")" == \
  "special:$SPECIAL_WORKSPACE_NAME" ]] || \
  fail "special workspace fixture moved unexpectedly: $fixture_special_state"
[[ "$(hyprctl activewindow -j | jq -r '.workspace.name // ""')" == \
  "special:$SPECIAL_WORKSPACE_NAME" ]] || \
  fail "special workspace was hidden while opening JotPin"
printf '%s\n' \
  'PASS: opening JotPin preserves the active special workspace'

if rg -q 'TypeError:|ReferenceError:|Binding loop detected|QQmlApplicationEngine' \
    "$OUTPUT_PATH"; then
  fail "native window test emitted a QML runtime error"
fi

printf '%s\n' \
  'PASS: centered and Side native window fullscreen, restore, and resize lifecycle'
