#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly TEST_TMP_DIR="$(mktemp -d /tmp/jotpin-native-markdown-display.XXXXXX)"
readonly CONFIG_DIR="$TEST_TMP_DIR/config"
readonly SCALE_VALUES=(1 1.25 1.6 2 3 4)
CURRENT_OUTPUT_PATH=""
declare -a SCALE_RESULTS=()

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  if [[ -n "$CURRENT_OUTPUT_PATH" && -f "$CURRENT_OUTPUT_PATH" ]]; then
    sed -n '1,260p' "$CURRENT_OUTPUT_PATH" >&2
  fi
  exit 1
}

cleanup() {
  rm -rf -- "$TEST_TMP_DIR"
}
trap cleanup EXIT

for command in quickshell timeout rg mktemp mkdir cp ln sed; do
  command -v "$command" >/dev/null 2>&1 || fail "$command is missing"
done

[[ -s "$ROOT_DIR/NativeMarkdownDisplay.qml" ]] || \
  fail "NativeMarkdownDisplay.qml is missing"
[[ -s "$ROOT_DIR/markdown/MarkdownParserWorker.js" ]] || \
  fail "markdown/MarkdownParserWorker.js is missing"
[[ -s "$ROOT_DIR/SyntaxHighlight.js" ]] || \
  fail "SyntaxHighlight.js is missing"
[[ -s "$ROOT_DIR/syntax/HighlightWorker.js" ]] || \
  fail "syntax/HighlightWorker.js is missing"

mkdir -m 700 -p -- "$CONFIG_DIR/markdown" "$CONFIG_DIR/syntax" \
  "$TEST_TMP_DIR/state" "$TEST_TMP_DIR/cache" "$TEST_TMP_DIR/data"
cp -- "$ROOT_DIR/tests/isolated/native_markdown_display_regression.qml" \
  "$CONFIG_DIR/shell.qml"
cp -- "$ROOT_DIR/NativeMarkdownDisplay.qml" "$CONFIG_DIR/"
cp -- "$ROOT_DIR/EditorModel.js" "$CONFIG_DIR/"
cp -- "$ROOT_DIR/SyntaxHighlight.js" "$CONFIG_DIR/"
cp -- "$ROOT_DIR/markdown/MarkdownParserWorker.js" \
  "$CONFIG_DIR/markdown/MarkdownParserWorker.js"
cp -- "$ROOT_DIR/syntax/HighlightWorker.js" \
  "$CONFIG_DIR/syntax/HighlightWorker.js"
cp -- "$ROOT_DIR/tests/fixtures/markdown-image.svg" \
  "$CONFIG_DIR/markdown-image.svg"
cp -- "$ROOT_DIR/tests/fixtures/markdown-image.svg" \
  "$TEST_TMP_DIR/markdown-image.svg"

# The native component may use the same Omarchy style imports as the existing
# renderer. Resolve those imports through read-only packaged modules while all
# writable XDG locations remain private to this run.
ln -s /usr/share/omarchy/shell/Commons "$CONFIG_DIR/Commons"
ln -s /usr/share/omarchy/shell/Ui "$CONFIG_DIR/Ui"

for scale in "${SCALE_VALUES[@]}"; do
  scale_key="${scale//./_}"
  runtime_dir="$TEST_TMP_DIR/runtime-$scale_key"
  output_path="$TEST_TMP_DIR/quickshell-$scale_key.log"
  CURRENT_OUTPUT_PATH="$output_path"
  mkdir -m 700 -p -- "$runtime_dir"
  if ! env -u QT_QPA_PLATFORMTHEME -u WAYLAND_DISPLAY -u DISPLAY \
      XDG_CONFIG_HOME="$CONFIG_DIR" XDG_STATE_HOME="$TEST_TMP_DIR/state" \
      XDG_CACHE_HOME="$TEST_TMP_DIR/cache" XDG_DATA_HOME="$TEST_TMP_DIR/data" \
      XDG_RUNTIME_DIR="$runtime_dir" QT_QPA_PLATFORM=offscreen \
      QT_SCALE_FACTOR="$scale" timeout --kill-after=1s 15s \
      quickshell --no-duplicate --path "$CONFIG_DIR/shell.qml" \
      >"$output_path" 2>&1; then
    fail "scale-$scale native Markdown display regression failed"
  fi
  if rg -q 'NATIVE_DISPLAY_FAIL:|ERROR qml:|ReferenceError:|TypeError:|SyntaxError:|Binding loop detected|Attempt to send message before WorkerScript establishment|QQmlApplicationEngine|file error|Failed to load' \
      "$output_path"; then
    fail "scale-$scale native Markdown display emitted a QML/runtime error"
  fi
  result_count="$(rg -c 'NATIVE_DISPLAY_RESULT: ' "$output_path" || true)"
  [[ "$result_count" -eq 1 ]] || \
    fail "scale-$scale display emitted $result_count results; expected 1"
  rg -q 'NATIVE_DISPLAY_RESULT: .*"failures":\[\]' "$output_path" || \
    fail "scale-$scale display reported failures"
  rg -q 'NATIVE_DISPLAY_RESULT: .*"sourceUnchanged":true' "$output_path" || \
    fail "scale-$scale display did not preserve canonical source"
  rg -q 'NATIVE_DISPLAY_RESULT: .*"metricCount":[1-9][0-9]*' "$output_path" || \
    fail "scale-$scale display reported empty layout metrics"
  rg -q 'NATIVE_DISPLAY_RESULT: .*"selectionRectangleCount":[1-9][0-9]*' "$output_path" || \
    fail "scale-$scale display reported empty selection geometry"
  result_line="$(rg 'NATIVE_DISPLAY_RESULT: ' "$output_path")"
  result_json="${result_line#*NATIVE_DISPLAY_RESULT: }"
  elapsed="$(printf '%s' "$result_json" | sed -n 's/.*"elapsedMs":\([0-9][0-9]*\).*/\1/p')"
  SCALE_RESULTS+=("$scale=${elapsed:-?}ms")
  printf 'NATIVE_DISPLAY_RESULT scale=%s: %s\n' "$scale" "$result_json"
done

CURRENT_OUTPUT_PATH=""
printf 'PASS: native Markdown display passed at Omarchy scales %s (%s)\n' \
  "${SCALE_VALUES[*]}" "${SCALE_RESULTS[*]}"
