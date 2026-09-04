#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-caret-matrix.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  [[ ! -f "$OUTPUT_PATH" ]] || sed -n '1,260p' "$OUTPUT_PATH" >&2
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg mktemp mkdir cp ln sed; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$CONFIG_DIR/syntax" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" "$TEST_TMP_DIR/data" \
  "$TEST_TMP_DIR/runtime"
cp -- "$ROOT_DIR/tests/isolated/native_markdown_caret_matrix.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" "$CONFIG_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" "$CONFIG_DIR/markdown/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/syntax/"
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    XDG_CONFIG_HOME="$CONFIG_DIR" XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$TEST_TMP_DIR/runtime" QT_QPA_PLATFORM=offscreen \
    timeout --kill-after=1s 20s quickshell --no-duplicate \
    --path "$CONFIG_DIR/shell.qml" >"$OUTPUT_PATH" 2>&1; then
  fail "native Markdown caret matrix failed"
fi

if rg -q 'CARET_MATRIX_FAIL:|ERROR qml:|ReferenceError:|TypeError:|SyntaxError:|Binding loop detected|QQmlApplicationEngine|Failed to load' \
    "$OUTPUT_PATH"; then
  fail "native Markdown caret matrix emitted a QML/runtime error"
fi
rg -q 'CARET_MATRIX_RESULT: .*"caseCount":13.*"checkedEdits":312.*"failures":\[\]' \
  "$OUTPUT_PATH" || fail "caret matrix did not validate all expected edits"
rg 'CARET_MATRIX_RESULT: ' "$OUTPUT_PATH"
printf 'PASS: rapid caret stability passed across 13 Markdown contexts\n'
