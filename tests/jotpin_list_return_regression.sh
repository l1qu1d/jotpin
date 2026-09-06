#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-list-return.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ ! -f "$OUTPUT_PATH" ]] || sed -n '1,260p' "$OUTPUT_PATH" >&2
  exit 1
}

for command in quickshell timeout mktemp mkdir cp ln rg; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done
mkdir -m 700 -p -- "$CONFIG_DIR/jotpin/markdown" \
  "$CONFIG_DIR/jotpin/spellcheck" "$CONFIG_DIR/jotpin/syntax" \
  "$TEST_TMP_DIR/runtime" "$TEST_TMP_DIR/cache" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/home"
cp -- "$ROOT_DIR/tests/isolated/jotpin_list_return.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/JotPin.qml" "$ROOT_DIR/JotPinButton.qml" \
  "$ROOT_DIR/HostIntegration.qml" "$ROOT_DIR/NativeMarkdownDisplay.qml" \
  "$ROOT_DIR/EditorModel.js" "$ROOT_DIR/HtmlEntities.js" \
  "$ROOT_DIR/SpellcheckModel.js" "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/jotpin/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/jotpin/markdown/"
cp -- "$ROOT_DIR/spellcheck/SpellcheckWorker.mjs" "$ROOT_DIR/spellcheck/DictionaryPart1.mjs" "$ROOT_DIR/spellcheck/DictionaryPart2.mjs" \
  "$CONFIG_DIR/jotpin/spellcheck/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$CONFIG_DIR/jotpin/syntax/"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

set +e
env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    HOME="$TEST_TMP_DIR/home" XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_RUNTIME_DIR="$TEST_TMP_DIR/runtime" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" QT_QPA_PLATFORM=minimal \
    timeout --kill-after=1s 15s quickshell --no-duplicate \
      --path "$CONFIG_DIR/shell.qml" \
      >"$OUTPUT_PATH" 2>&1
status=$?
set -e

if [[ "$status" -ne 0 ]]; then
  fail "JotPin list Return regression failed (Quickshell status $status)"
fi
if rg -q 'LIST_RETURN_FAIL:|QFATAL|ReferenceError:|TypeError:|SyntaxError:|Binding loop' \
    "$OUTPUT_PATH"; then
  fail "JotPin list Return regression reported a failure or runtime error"
fi
rg -q 'LIST_RETURN_RESULT: pass' "$OUTPUT_PATH" || \
  fail "JotPin list Return regression did not report a clean summary"

printf '%s\n' \
  'PASS: Return at a wrapped list-item end creates an empty bullet before the existing next item'
