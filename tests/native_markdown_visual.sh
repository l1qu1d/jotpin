#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-markdown-visual.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly RUNTIME_DIR="$TEST_TMP_DIR/runtime"
readonly OUTPUT_PATH="$TEST_TMP_DIR/quickshell.log"
readonly CAPTURE_PATH="${JOTPIN_NATIVE_CAPTURE_PATH:-/tmp/jotpin-native-markdown.png}"

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$CONFIG_DIR/syntax" \
  "$RUNTIME_DIR" "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" \
  "$TEST_TMP_DIR/data"
cp -- "$ROOT_DIR/tests/isolated/native_markdown_visual.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$ROOT_DIR/EditorModel.js" \
  "$ROOT_DIR/SyntaxHighlight.js" \
  "$CONFIG_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" "$CONFIG_DIR/markdown/"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" "$CONFIG_DIR/syntax/"

if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
    JOTPIN_NATIVE_CAPTURE_PATH="$CAPTURE_PATH" \
    XDG_CONFIG_HOME="$CONFIG_DIR" XDG_STATE_HOME="$TEST_TMP_DIR/state" \
    XDG_CACHE_HOME="$TEST_TMP_DIR/cache" XDG_DATA_HOME="$TEST_TMP_DIR/data" \
    XDG_RUNTIME_DIR="$RUNTIME_DIR" QT_QPA_PLATFORM=offscreen \
    timeout --kill-after=1s 10s \
    quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
    >"$OUTPUT_PATH" 2>&1; then
  sed -n '1,260p' "$OUTPUT_PATH" >&2
  exit 1
fi

if rg -q 'NATIVE_VISUAL_FAIL:|ERROR qml:|ReferenceError:|TypeError:|SyntaxError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine|Failed to load' \
    "$OUTPUT_PATH"; then
  sed -n '1,260p' "$OUTPUT_PATH" >&2
  exit 1
fi
[[ -s "$CAPTURE_PATH" ]] || {
  printf 'FAIL: native visual artifact was not written\n' >&2
  exit 1
}
printf 'NATIVE_VISUAL_RESULT: %s\n' "$CAPTURE_PATH"
