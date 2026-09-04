#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-link-keys.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -f "$OUTPUT_PATH" ]]; then
    sed -n '1,320p' "$OUTPUT_PATH" >&2
  fi
  exit 1
}

for command in quickshell timeout mktemp mkdir cp ln rg sed; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

[[ -s "$ROOT_DIR/JotPin.qml" ]] || fail "JotPin.qml is missing"
[[ -s "$ROOT_DIR/NativeMarkdownDisplay.qml" ]] || \
  fail "NativeMarkdownDisplay.qml is missing"
[[ -s "$ROOT_DIR/markdown/MarkdownParserWorker.js" ]] || \
  fail "the Markdown parser worker is missing"
[[ -s "$ROOT_DIR/syntax/HighlightWorker.js" ]] || \
  fail "the syntax worker is missing"

mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/markdown" \
  "$CONFIG_DIR/jotpin/spellcheck" "$CONFIG_DIR/jotpin/syntax" \
  "$TEST_TMP_DIR/home" "$TEST_TMP_DIR/runtime" "$TEST_TMP_DIR/cache" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/data"
mkdir -p "$TEST_TMP_DIR/home/Documents/Notes" "$CONFIG_DIR/jotpin/assets"
cp "$ROOT_DIR/tests/fixtures/persistence-base.md" "$TEST_TMP_DIR/home/Documents/Notes/welcome.md"
cp "$ROOT_DIR/assets/jotpin-icon.png" "$CONFIG_DIR/jotpin/assets/"

cp -- "$ROOT_DIR/tests/isolated/jotpin_link_keys.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/JotPin.qml" "$ROOT_DIR/JotPinButton.qml" \
  "$ROOT_DIR/HostIntegration.qml" "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  "$ROOT_DIR/EditorModel.js" "$ROOT_DIR/HtmlEntities.js" \
  "$ROOT_DIR/SpellcheckModel.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/jotpin/markdown/"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.js" \
  "$CONFIG_DIR/jotpin/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$CONFIG_DIR/jotpin/syntax/"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

set +e
env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    HOME="$TEST_TMP_DIR/home" XDG_CONFIG_HOME="$CONFIG_DIR" \
    XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$TEST_TMP_DIR/runtime" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout --kill-after=1s 30s quickshell --no-duplicate \
      --path "$CONFIG_DIR/shell.qml" >"$OUTPUT_PATH" 2>&1
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  fail "JotPin Ctrl-key integration regression failed (Quickshell status $status)"
fi
if rg -q 'JOTPIN_LINK_KEYS_FAIL:|FAIL!|QFATAL|ReferenceError:|TypeError:|SyntaxError:|Binding loop|QQmlApplicationEngine|Failed to load' \
    "$OUTPUT_PATH"; then
  fail "JotPin Ctrl-key integration regression reported a failure or runtime error"
fi
[[ "$(rg -c 'JOTPIN_LINK_KEYS_RESULT: pass' "$OUTPUT_PATH" || true)" == 1 ]] || \
  fail "JotPin Ctrl-key integration regression did not report a clean result"

printf '%s\n' \
  'PASS: synthetic Qt Ctrl press/release reaches JotPin and controls the renderer marker' \
  'PASS: blank-space Ctrl hover stays marker-free' \
  'PASS: real product clicks dispatch one exact URL only with Ctrl' \
  'PASS: native focus loss clears the held Ctrl state and marker'
